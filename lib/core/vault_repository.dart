import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'flashcards.dart';
import 'vault_index.dart';

/// All file-system access to an Obsidian vault lives here.
class VaultRepository {
  VaultRepository(this.root);

  final String root;

  /// App data kept inside the vault; Obsidian ignores dot-folders.
  static const appDir = '.fptu';

  String abs(String rel) => p.joinAll([root, ...rel.split('/')]);
  String rel(String absPath) => p.relative(absPath, from: root).replaceAll('\\', '/');

  static bool isNotePath(String relPath) =>
      relPath.toLowerCase().endsWith('.md') && !relPath.split('/').any((s) => s.startsWith('.'));

  Future<List<Note>> loadAll() async {
    final dir = Directory(root);
    if (!await dir.exists()) throw FileSystemException('Không tìm thấy thư mục vault', root);
    final notes = <Note>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final r = rel(e.path);
      if (!isNotePath(r)) continue;
      final n = await readNote(r);
      if (n != null) notes.add(n);
    }
    return notes;
  }

  Future<Note?> readNote(String relPath) async {
    final f = File(abs(relPath));
    try {
      final content = await f.readAsString();
      return Note.parse(relPath, content, await f.lastModified());
    } on FileSystemException {
      return null;
    } on FormatException {
      // Not valid UTF-8: skip rather than crash the whole index.
      return null;
    }
  }

  Future<Note> writeNote(String relPath, String content) async {
    final f = File(abs(relPath));
    await f.parent.create(recursive: true);
    await f.writeAsString(content, flush: true);
    return Note.parse(relPath, content, DateTime.now());
  }

  /// Creates a new note with a unique name inside [folder].
  Future<Note> createNote(String folder, String title, {String content = ''}) async {
    final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]]'), '-').trim();
    final base = safe.isEmpty ? 'Ghi chú mới' : safe;
    var name = base;
    var i = 1;
    String path() => folder.isEmpty ? '$name.md' : '$folder/$name.md';
    while (await File(abs(path())).exists()) {
      name = '$base ${i++}';
    }
    return writeNote(path(), content.isEmpty ? '# $name\n\n' : content);
  }

  /// Moves a note to `.trash/` like Obsidian's "Move to vault trash" option.
  Future<void> trashNote(String relPath) async {
    final src = File(abs(relPath));
    final dest = File(p.join(root, '.trash', '${DateTime.now().millisecondsSinceEpoch}_${p.basename(relPath)}'));
    await dest.parent.create(recursive: true);
    await src.rename(dest.path);
  }

  Stream<WatchEvent> watch() => DirectoryWatcher(root).events;

  File get _srsFile => File(p.join(root, appDir, 'srs.json'));

  Future<Map<String, CardState>> loadSrs() async {
    try {
      final j = jsonDecode(await _srsFile.readAsString()) as Map<String, dynamic>;
      final cards = j['cards'] as Map<String, dynamic>? ?? {};
      return cards.map((k, v) => MapEntry(k, CardState.fromJson(v as Map<String, dynamic>)));
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<void> saveSrs(Map<String, CardState> states) async {
    await _srsFile.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _srsFile.writeAsString(
      encoder.convert({'version': 1, 'cards': states.map((k, v) => MapEntry(k, v.toJson()))}),
      flush: true,
    );
  }
}
