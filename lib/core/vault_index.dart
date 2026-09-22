import 'package:path/path.dart' as p;

import 'markdown_utils.dart';

enum CourseStatus {
  todo('Chưa học'),
  learning('Đang học'),
  done('Hoàn thành');

  const CourseStatus(this.label);
  final String label;

  static CourseStatus parse(Object? v) => values.firstWhere((s) => s.name == v?.toString(), orElse: () => todo);
}

class Note {
  Note._({
    required this.path,
    required this.content,
    required this.frontmatter,
    required this.body,
    required this.links,
    required this.tags,
    required this.modified,
  });

  factory Note.parse(String path, String content, DateTime modified) {
    final fm = splitFrontmatter(content);
    return Note._(
      path: path,
      content: content,
      frontmatter: fm.data,
      body: fm.body,
      links: parseWikiLinks(fm.body).where((l) => !isImageTarget(l.target)).toList(),
      tags: {
        ...asStringList(fm.data['tags']).map((t) => t.replaceFirst('#', '').toLowerCase()),
        ...parseInlineTags(fm.body),
      },
      modified: modified,
    );
  }

  /// Vault-relative path with `/` separators, e.g. `Courses/PRF192.md`.
  final String path;
  final String content;
  final Map<String, dynamic> frontmatter;
  final String body;
  final List<WikiLink> links;
  final Set<String> tags;
  final DateTime modified;

  String get title => p.posix.basenameWithoutExtension(path);
  String get folder {
    final d = p.posix.dirname(path);
    return d == '.' ? '' : d;
  }

  List<String> get aliases => asStringList(frontmatter['aliases']);
  bool get isCourse => frontmatter['type'] == 'course';
  String get courseCode => (frontmatter['code'] ?? title).toString();
  String get courseName => (frontmatter['name'] ?? '').toString();
  int get semester => int.tryParse('${frontmatter['semester']}') ?? 0;
  CourseStatus get status => CourseStatus.parse(frontmatter['status']);
  List<String> get prerequisites => asStringList(frontmatter['prerequisites']);
}

class SearchHit {
  SearchHit(this.note, this.score, this.snippet, this.matchStart, this.matchEnd);
  final Note note;
  final int score;
  final String snippet;
  final int matchStart;
  final int matchEnd;
}

/// Immutable in-memory index of a vault: notes, link resolution, backlinks.
class VaultIndex {
  VaultIndex(this.root, Iterable<Note> notes, {Iterable<String> attachments = const []})
    : notes = {for (final n in notes) n.path: n},
      attachments = {for (final a in attachments) a.toLowerCase(): a} {
    for (final a in this.attachments.values) {
      _attachByName.putIfAbsent(p.posix.basename(a).toLowerCase(), () => a);
    }
    for (final n in this.notes.values) {
      _byName.putIfAbsent(n.title.toLowerCase(), () => n.path);
      _byName.putIfAbsent(p.posix.withoutExtension(n.path).toLowerCase(), () => n.path);
      for (final a in n.aliases) {
        _byName.putIfAbsent(a.toLowerCase(), () => n.path);
      }
    }
    for (final n in this.notes.values) {
      for (final l in n.links) {
        final target = resolve(l.target);
        if (target != null && target != n.path) {
          (backlinks[target] ??= <String>{}).add(n.path);
          (outgoing[n.path] ??= <String>{}).add(target);
        }
      }
    }
  }

  final String root;
  final Map<String, Note> notes;
  final Map<String, String> _byName = {};

  /// Non-note files Obsidian can embed (images), keyed by lower-cased path.
  final Map<String, String> attachments;
  final Map<String, String> _attachByName = {};
  final Map<String, Set<String>> backlinks = {};
  final Map<String, Set<String>> outgoing = {};

  String get name => p.basename(root);

  /// Resolves a wikilink target the way Obsidian does: by path, file name or alias.
  String? resolve(String target) {
    var t = target.trim().replaceAll('\\', '/').toLowerCase();
    if (t.endsWith('.md')) t = t.substring(0, t.length - 3);
    return _byName[t];
  }

  /// Resolves an embed like `![[diagram.png]]` or `![](img/a.png)`: exact vault
  /// path, then relative to [fromFolder], then by file name anywhere (Obsidian's default).
  String? resolveAttachment(String target, {String fromFolder = ''}) {
    final t = p.posix.normalize(target.trim().replaceAll(r'\', '/')).toLowerCase();
    if (fromFolder.isNotEmpty) {
      final rel = attachments[p.posix.normalize(p.posix.join(fromFolder.toLowerCase(), t))];
      if (rel != null) return rel;
    }
    return attachments[t] ?? _attachByName[p.posix.basename(t)];
  }

  VaultIndex withNote(Note note) =>
      VaultIndex(root, {...notes, note.path: note}.values, attachments: attachments.values);
  VaultIndex without(String path) =>
      VaultIndex(root, notes.values.where((n) => n.path != path), attachments: attachments.values);
  VaultIndex withAttachments(Iterable<String> paths) => VaultIndex(root, notes.values, attachments: paths);

  List<Note> get courses => notes.values.where((n) => n.isCourse).toList()
    ..sort(
      (a, b) => a.semester != b.semester ? a.semester.compareTo(b.semester) : a.courseCode.compareTo(b.courseCode),
    );

  List<Note> get recent => notes.values.toList()..sort((a, b) => b.modified.compareTo(a.modified));

  Map<String, int> get tagCounts {
    final counts = <String, int>{};
    for (final n in notes.values) {
      for (final t in n.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  int get linkCount => outgoing.values.fold(0, (s, e) => s + e.length);

  /// Accent-insensitive full-text search. `#tag` searches tags.
  /// All terms must match; title matches rank highest.
  List<SearchHit> search(String query, {int limit = 100}) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    if (q.startsWith('#')) {
      final tag = q.substring(1).toLowerCase();
      return notes.values
          .where((n) => n.tags.any((t) => t == tag || t.startsWith('$tag/')))
          .map((n) => SearchHit(n, 1, _firstLine(n.body), 0, 0))
          .toList();
    }
    final terms = foldVietnamese(q).split(RegExp(r'\s+'));
    final hits = <SearchHit>[];
    for (final n in notes.values) {
      final title = foldVietnamese(n.title);
      final body = foldVietnamese(n.content);
      var score = 0;
      var ok = true;
      for (final t in terms) {
        final inTitle = title.contains(t);
        final count = t.allMatches(body).length;
        if (!inTitle && count == 0) {
          ok = false;
          break;
        }
        score += (inTitle ? 50 : 0) + (title == t ? 50 : 0) + count;
      }
      if (!ok) continue;
      final idx = body.indexOf(terms.first);
      if (idx < 0) {
        hits.add(SearchHit(n, score, _firstLine(n.body), 0, 0));
        continue;
      }
      final start = (idx - 60).clamp(0, n.content.length);
      final end = (idx + terms.first.length + 100).clamp(0, n.content.length);
      final snippet = n.content.substring(start, end).replaceAll('\n', ' ');
      hits.add(
        SearchHit(
          n,
          score,
          '${start > 0 ? '…' : ''}$snippet${end < n.content.length ? '…' : ''}',
          idx - start + (start > 0 ? 1 : 0),
          idx - start + (start > 0 ? 1 : 0) + terms.first.length,
        ),
      );
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  static String _firstLine(String body) =>
      body.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty && !l.startsWith('#'), orElse: () => '');
}
