import 'package:path/path.dart' as p;

import 'markdown_utils.dart';
import 'vault_index.dart';

/// An unfinished `[[...` the cursor is currently inside.
class WikilinkQuery {
  const WikilinkQuery(this.start, this.query);

  /// Index of the first `[` of `[[`.
  final int start;

  /// Text typed between `[[` and the cursor.
  final String query;
}

/// Returns the open wikilink under [cursor], or null when the cursor is not
/// inside `[[` on the current line (already closed, alias/heading part, code).
WikilinkQuery? activeWikilinkQuery(String text, int cursor) {
  if (cursor < 2 || cursor > text.length) return null;
  final lineStart = text.lastIndexOf('\n', cursor - 1) + 1;
  final before = text.substring(lineStart, cursor);
  final open = before.lastIndexOf('[[');
  if (open < 0) return null;
  final query = before.substring(open + 2);
  if (query.contains(']]') || query.contains('|') || query.contains('#') || query.contains('[')) return null;
  // Skip inline code: an odd number of backticks before `[[` means we're inside one.
  if ('`'.allMatches(before.substring(0, open)).length.isOdd) return null;
  return WikilinkQuery(lineStart + open, query);
}

class LinkSuggestion {
  const LinkSuggestion(this.note, {this.alias});
  final Note note;

  /// Set when the match came from the note's `aliases`.
  final String? alias;
}

/// Ranks notes for a `[[query`: exact > prefix > contains, titles before
/// aliases before paths. Accent-insensitive. Empty query = most recent notes.
List<LinkSuggestion> suggestLinks(VaultIndex index, String query, {String? exclude, int limit = 8}) {
  final q = foldVietnamese(query.trim());
  final candidates = index.notes.values.where((n) => n.path != exclude);
  if (q.isEmpty) {
    return (candidates.toList()..sort((a, b) => b.modified.compareTo(a.modified)))
        .take(limit)
        .map(LinkSuggestion.new)
        .toList();
  }
  final scored = <(int, LinkSuggestion)>[];
  for (final n in candidates) {
    final title = foldVietnamese(n.title);
    int? score = title == q
        ? 0
        : title.startsWith(q)
        ? 1
        : title.contains(q)
        ? 3
        : null;
    String? alias;
    if (score == null || score > 2) {
      for (final a in n.aliases) {
        final fa = foldVietnamese(a);
        final s = fa == q || fa.startsWith(q) ? 2 : (fa.contains(q) ? 4 : null);
        if (s != null && (score == null || s < score)) {
          score = s;
          alias = a;
        }
      }
    }
    if (score == null && foldVietnamese(n.path).contains(q)) score = 5;
    if (score != null) scored.add((score, LinkSuggestion(n, alias: alias)));
  }
  scored.sort((a, b) {
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    final len = a.$2.note.title.length.compareTo(b.$2.note.title.length);
    return len != 0 ? len : a.$2.note.title.compareTo(b.$2.note.title);
  });
  return scored.take(limit).map((e) => e.$2).toList();
}

/// The text to put between `[[` and `]]` so the link resolves to [s]:
/// the bare title, or the path when another note shares the name, plus `|alias`.
String linkTarget(VaultIndex index, LinkSuggestion s) {
  final title = s.note.title;
  final target = index.resolve(title) == s.note.path ? title : p.posix.withoutExtension(s.note.path);
  return s.alias == null ? target : '$target|${s.alias}';
}

/// Replaces `[[query` (from [q].start up to [cursor]) with `[[target]]` and
/// puts the cursor after the closing brackets. Reuses an existing `]]`.
({String text, int cursor}) applyWikilinkCompletion(String text, int cursor, WikilinkQuery q, String target) {
  final hasClose = text.startsWith(']]', cursor);
  final insert = '[[$target]]';
  final end = hasClose ? cursor + 2 : cursor;
  final newText = text.replaceRange(q.start, end, insert);
  return (text: newText, cursor: q.start + insert.length);
}
