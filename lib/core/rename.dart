import 'package:path/path.dart' as p;

import 'vault_index.dart';

final _linkRe = RegExp(r'(!?)\[\[([^\[\]\n|#]+)((?:#[^\[\]\n|]*)?(?:\|[^\[\]\n]*)?)\]\]');

/// Rewrites the target of every `[[target#heading|alias]]` (and `![[...]]`)
/// for which [matches] is true, keeping heading, alias and embed marker.
/// Code blocks are left untouched.
String replaceLinkTargets(String content, bool Function(String target) matches, String newTarget) {
  final parts = content.split('```');
  for (var i = 0; i < parts.length; i += 2) {
    parts[i] = parts[i].replaceAllMapped(_linkRe, (m) {
      final target = m.group(2)!.trim();
      if (!matches(target)) return m.group(0)!;
      return '${m.group(1)}[[$newTarget${m.group(3)}]]';
    });
  }
  return parts.join('```');
}

/// Characters Obsidian doesn't allow in file names.
final invalidNameChars = RegExp(r'[\\/:*?"<>|#^\[\]]');

class RenamePlan {
  const RenamePlan(this.newPath, this.updates);
  final String newPath;

  /// New content for every note whose links change, keyed by its path
  /// *after* the rename (the renamed note itself appears under [newPath]).
  final Map<String, String> updates;

  int get linkedNotes => updates.length;
}

/// Works out the new path and the link rewrites for renaming [oldPath] to
/// [newTitle] (same folder). Links written with an alias of the note keep
/// working and are not touched.
RenamePlan planRename(VaultIndex index, String oldPath, String newTitle) {
  final note = index.notes[oldPath]!;
  final folder = note.folder;
  final newPath = folder.isEmpty ? '$newTitle.md' : '$folder/$newTitle.md';
  final after = VaultIndex(index.root, [
    for (final n in index.notes.values)
      if (n.path != oldPath) n,
    Note.parse(newPath, note.content, note.modified),
  ], attachments: index.attachments.values);
  // Bare title when it resolves uniquely, otherwise the path without `.md`.
  final newTarget = after.resolve(newTitle) == newPath ? newTitle : p.posix.withoutExtension(newPath);
  final aliases = note.aliases.map((a) => a.toLowerCase()).toSet();
  bool pointsToOld(String t) => index.resolve(t) == oldPath && !aliases.contains(t.toLowerCase());

  final updates = <String, String>{};
  for (final n in index.notes.values) {
    if (!n.links.any((l) => pointsToOld(l.target))) continue;
    final updated = replaceLinkTargets(n.content, pointsToOld, newTarget);
    if (updated != n.content) updates[n.path == oldPath ? newPath : n.path] = updated;
  }
  return RenamePlan(newPath, updates);
}
