import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'flashcards.dart';
import 'review_stats.dart';
import 'vault_index.dart';

class NoteConflictException implements Exception {
  const NoteConflictException(this.path, this.diskContent);

  final String path;
  final String diskContent;

  @override
  String toString() => 'Ghi chú "$path" đã được thay đổi bởi ứng dụng khác.';
}

class TrashedNote {
  const TrashedNote({
    required this.trashPath,
    required this.originalPath,
    required this.deletedAt,
  });

  final String trashPath;
  final String originalPath;
  final DateTime deletedAt;
}

/// All file-system access to an Obsidian vault lives here.
class VaultRepository {
  VaultRepository(this.root);

  final String root;

  /// App data kept inside the vault; Obsidian ignores dot-folders.
  static const appDir = '.fptu';

  String abs(String rel) => p.joinAll([root, ...rel.split('/')]);
  String rel(String absPath) =>
      p.relative(absPath, from: root).replaceAll('\\', '/');

  static bool isNotePath(String relPath) =>
      relPath.toLowerCase().endsWith('.md') &&
      !relPath.split('/').any((s) => s.startsWith('.'));

  static const imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  };

  static bool isAttachmentPath(String relPath) =>
      imageExtensions.contains(p.extension(relPath).toLowerCase()) &&
      !relPath.split('/').any((s) => s.startsWith('.'));

  /// Scans the vault once for notes and embeddable images.
  Future<VaultIndex> loadIndex() async {
    final dir = Directory(root);
    if (!await dir.exists()) {
      throw FileSystemException('Không tìm thấy thư mục vault', root);
    }
    final notes = <Note>[];
    final attachments = <String>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final r = rel(e.path);
      if (isAttachmentPath(r)) {
        attachments.add(r);
      } else if (isNotePath(r)) {
        final n = await readNote(r);
        if (n != null) notes.add(n);
      }
    }
    return VaultIndex(root, notes, attachments: attachments);
  }

  Future<List<Note>> loadAll() async =>
      (await loadIndex()).notes.values.toList();

  /// Renames/moves a file inside the vault. Fails if the target exists.
  Future<void> renameFile(String fromRel, String toRel) async {
    final dest = File(abs(toRel));
    if (await dest.exists()) {
      throw FileSystemException('Đã có file trùng tên', toRel);
    }
    await dest.parent.create(recursive: true);
    await File(abs(fromRel)).rename(dest.path);
  }

  /// Copies an image from anywhere on disk into `attachments/` (unique name)
  /// and returns its vault-relative path.
  Future<String> importAttachment(
    String sourcePath, {
    String folder = 'attachments',
  }) async {
    final base = p
        .basenameWithoutExtension(sourcePath)
        .replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]]'), '-');
    final ext = p.extension(sourcePath).toLowerCase();
    var name = '$base$ext';
    for (var i = 1; await File(abs('$folder/$name')).exists(); i++) {
      name = '$base $i$ext';
    }
    final dest = File(abs('$folder/$name'));
    await dest.parent.create(recursive: true);
    await File(sourcePath).copy(dest.path);
    return '$folder/$name';
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

  Future<Note> writeNote(
    String relPath,
    String content, {
    String? expectedContent,
  }) async {
    final f = File(abs(relPath));
    await f.parent.create(recursive: true);
    if (expectedContent != null && await f.exists()) {
      final diskContent = await f.readAsString();
      if (diskContent != expectedContent) {
        throw NoteConflictException(relPath, diskContent);
      }
    }
    await _atomicWrite(f, content);
    return Note.parse(relPath, content, await f.lastModified());
  }

  /// Creates a new note with a unique name inside [folder].
  Future<Note> createNote(
    String folder,
    String title, {
    String content = '',
  }) async {
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

  /// Moves a note to `.trash/<timestamp>/<original path>`, preserving enough
  /// information for the app to restore it to its former folder.
  Future<void> trashNote(String relPath) async {
    final src = File(abs(relPath));
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final dest = File(
      p.joinAll([root, '.trash', stamp, ...relPath.split('/')]),
    );
    await dest.parent.create(recursive: true);
    await src.rename(dest.path);
  }

  Future<List<TrashedNote>> listTrash() async {
    final trash = Directory(p.join(root, '.trash'));
    if (!await trash.exists()) return [];
    final result = <TrashedNote>[];
    await for (final entity in trash.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.md') {
        continue;
      }
      final relative = p
          .relative(entity.path, from: trash.path)
          .replaceAll('\\', '/');
      final parts = relative.split('/');
      final stamp = parts.length > 1 ? int.tryParse(parts.first) : null;
      final original = parts.length > 1 && stamp != null
          ? parts.skip(1).join('/')
          : p.basename(entity.path);
      result.add(
        TrashedNote(
          trashPath: relative,
          originalPath: original,
          deletedAt: stamp == null
              ? await entity.lastModified()
              : DateTime.fromMillisecondsSinceEpoch(stamp),
        ),
      );
    }
    result.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return result;
  }

  /// Restores a trashed note. A numeric suffix is added when the original path
  /// is already occupied, so restoring never overwrites a current note.
  Future<Note> restoreTrash(TrashedNote entry) async {
    final src = File(
      p.joinAll([root, '.trash', ...entry.trashPath.split('/')]),
    );
    if (!await src.exists()) {
      throw FileSystemException(
        'Không tìm thấy ghi chú trong thùng rác',
        src.path,
      );
    }
    var targetPath = entry.originalPath;
    final ext = p.extension(targetPath);
    final stem = targetPath.substring(0, targetPath.length - ext.length);
    for (var i = 1; await File(abs(targetPath)).exists(); i++) {
      targetPath = '$stem (khôi phục $i)$ext';
    }
    final dest = File(abs(targetPath));
    await dest.parent.create(recursive: true);
    await src.rename(dest.path);
    return (await readNote(targetPath))!;
  }

  Stream<WatchEvent> watch() => DirectoryWatcher(root).events;

  File get _srsFile => File(p.join(root, appDir, 'srs.json'));

  Future<Map<String, CardState>> loadSrs() async {
    try {
      final j =
          jsonDecode(await _srsFile.readAsString()) as Map<String, dynamic>;
      final cards = j['cards'] as Map<String, dynamic>? ?? {};
      return cards.map(
        (k, v) => MapEntry(k, CardState.fromJson(v as Map<String, dynamic>)),
      );
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  File get _logFile => File(p.join(root, appDir, 'review_log.json'));

  Future<List<ReviewEntry>> loadReviewLog() async {
    try {
      final j =
          jsonDecode(await _logFile.readAsString()) as Map<String, dynamic>;
      return (j['reviews'] as List? ?? const [])
          .map(ReviewEntry.fromJson)
          .whereType<ReviewEntry>()
          .toList();
    } on FileSystemException {
      return [];
    } on FormatException {
      return [];
    }
  }

  Future<void> saveReviewLog(List<ReviewEntry> log) async {
    await _logFile.parent.create(recursive: true);
    await _atomicWrite(
      _logFile,
      jsonEncode({
        'version': 1,
        'reviews': [for (final e in log) e.toJson()],
      }),
    );
  }

  Future<void> saveSrs(Map<String, CardState> states) async {
    await _srsFile.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _atomicWrite(
      _srsFile,
      encoder.convert({
        'version': 1,
        'cards': states.map((k, v) => MapEntry(k, v.toJson())),
      }),
    );
  }

  Future<void> _atomicWrite(File target, String content) async {
    final nonce = '${DateTime.now().microsecondsSinceEpoch}_$pid';
    final temp = File('${target.path}.$nonce.tmp');
    final backup = File('${target.path}.$nonce.bak');
    await temp.writeAsString(content, flush: true);
    final existed = await target.exists();
    try {
      if (existed) await target.rename(backup.path);
      await temp.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
      if (await backup.exists() && await target.exists()) await backup.delete();
    }
  }
}
