import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_brain/core/flashcards.dart';
import 'package:fptu_brain/core/markdown_utils.dart';
import 'package:fptu_brain/core/rename.dart';
import 'package:fptu_brain/core/vault_index.dart';
import 'package:fptu_brain/core/vault_repository.dart';
import 'package:fptu_brain/state/providers.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Note note(String path, String content) => Note.parse(path, content, DateTime(2026));

void main() {
  group('replaceLinkTargets', () {
    test('keeps heading, alias and embed marker; skips code blocks', () {
      const src = '[[OOP]] [[OOP#Kế thừa|kế thừa]] ![[OOP]] [[Other]]\n```\n[[OOP]]\n```';
      final out = replaceLinkTargets(src, (t) => t == 'OOP', 'Lập trình OOP');
      expect(
        out,
        '[[Lập trình OOP]] [[Lập trình OOP#Kế thừa|kế thừa]] ![[Lập trình OOP]] [[Other]]\n```\n[[OOP]]\n```',
      );
    });
  });

  group('planRename', () {
    final index = VaultIndex('/v', [
      note('Concepts/OOP.md', '---\naliases: [Hướng đối tượng]\n---\nXem [[OOP]] và [[MVC]]'),
      note('Courses/PRO192.md', '- [[OOP]]\n- [[Concepts/OOP|khái niệm]]\n- [[Hướng đối tượng]]'),
      note('Concepts/MVC.md', 'Dựa trên [[oop#Đa hình]]'),
      note('Archive/Lập trình OOP.md', ''),
      note('Home.md', 'Không liên quan [[MVC]]'),
    ]);

    test('rewrites every link to the note except alias links', () {
      final plan = planRename(index, 'Concepts/OOP.md', 'Lập trình OOP');
      expect(plan.newPath, 'Concepts/Lập trình OOP.md');
      // Another note already has that title, so links use the path form.
      expect(
        plan.updates['Courses/PRO192.md'],
        '- [[Concepts/Lập trình OOP]]\n- [[Concepts/Lập trình OOP|khái niệm]]\n- [[Hướng đối tượng]]',
      );
      expect(plan.updates['Concepts/MVC.md'], 'Dựa trên [[Concepts/Lập trình OOP#Đa hình]]');
      expect(plan.updates['Concepts/Lập trình OOP.md'], contains('Xem [[Concepts/Lập trình OOP]] và [[MVC]]'));
      expect(plan.updates.containsKey('Home.md'), isFalse);
      expect(plan.linkedNotes, 3);
    });

    test('uses the bare title when it is unique', () {
      final plan = planRename(index, 'Concepts/MVC.md', 'Model View Controller');
      expect(plan.updates['Concepts/OOP.md'], contains('[[Model View Controller]]'));
      expect(plan.updates['Home.md'], 'Không liên quan [[Model View Controller]]');
    });
  });

  group('images', () {
    test('image embeds render as images with width and are not note links', () {
      expect(obsidianToMarkdown('![[sơ đồ.png|300]]'), '![300](vaultimg:s%C6%A1%20%C4%91%E1%BB%93.png)');
      expect(obsidianToMarkdown('![[Other note]]'), '[Other note](wikilink:Other%20note)');
      final n = note('a.md', '![[diagram.PNG]] [[B]]');
      expect(n.links.map((l) => l.target), ['B']);
    });

    test('resolveAttachment: exact path, relative to note, then by file name', () {
      final index = VaultIndex('/v', const [], attachments: ['attachments/uml.png', 'Courses/img/erd.jpg']);
      expect(index.resolveAttachment('uml.png'), 'attachments/uml.png');
      expect(index.resolveAttachment('attachments/UML.png'), 'attachments/uml.png');
      expect(index.resolveAttachment('img/erd.jpg', fromFolder: 'Courses'), 'Courses/img/erd.jpg');
      expect(index.resolveAttachment('../Courses/img/erd.jpg', fromFolder: 'Concepts'), 'Courses/img/erd.jpg');
      expect(index.resolveAttachment('missing.png'), isNull);
    });
  });

  test('repository indexes images, imports with unique names and renames files', () async {
    final dir = await Directory.systemTemp.createTemp('fptu_repo');
    addTearDown(() => dir.delete(recursive: true));
    final repo = VaultRepository(dir.path);
    await repo.writeNote('A.md', '![[pic.png]]');
    final src = File(p.join(dir.path, '..', 'fptu_src_${DateTime.now().microsecondsSinceEpoch}.png'));
    await src.writeAsBytes([137, 80, 78, 71]);
    addTearDown(() => src.delete());

    expect(await repo.importAttachment(src.path), startsWith('attachments/fptu_src_'));
    final second = await repo.importAttachment(src.path);
    expect(second, endsWith(' 1.png'));
    final index = await repo.loadIndex();
    expect(index.attachments.length, 2);
    expect(index.notes.keys, ['A.md']);

    await repo.renameFile('A.md', 'B.md');
    expect(await File(p.join(dir.path, 'B.md')).exists(), isTrue);
    expect(() => repo.renameFile('B.md', 'B.md'), throwsA(isA<FileSystemException>()));
  });

  test('VaultNotifier.rename moves the file, updates links and keeps review history', () async {
    final dir = await Directory.systemTemp.createTemp('fptu_rename');
    final repo = VaultRepository(dir.path);
    await repo.writeNote('Concepts/OOP.md', '# OOP\nOOP là gì?::Lập trình hướng đối tượng');
    await repo.writeNote('Courses/PRO192.md', '- [[OOP]]');
    await repo.saveSrs({'Concepts/OOP.md|OOP là gì?': const CardState(interval: 6, reps: 2)});

    SharedPreferences.setMockInitialValues({'vaultPath': dir.path});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    addTearDown(() async {
      c.dispose();
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Watcher may still hold the directory on Windows.
      }
    });
    c.listen(vaultProvider, (_, _) {});
    c.listen(srsProvider, (_, _) {});
    await c.read(vaultProvider.future);
    await c.read(srsProvider.future);

    final r = await c.read(vaultProvider.notifier).rename('Concepts/OOP.md', 'Lập trình hướng đối tượng');
    expect(r.path, 'Concepts/Lập trình hướng đối tượng.md');
    expect(r.linkedNotes, 1);
    expect(await File(p.join(dir.path, 'Concepts', 'OOP.md')).exists(), isFalse);
    expect(await File(p.join(dir.path, 'Courses', 'PRO192.md')).readAsString(), '- [[Lập trình hướng đối tượng]]');
    final index = c.read(vaultProvider).value!;
    expect(index.backlinks[r.path], {'Courses/PRO192.md'});
    expect(c.read(srsProvider).value!['${r.path}|OOP là gì?']!.interval, 6);
    expect((await repo.loadSrs()).keys, ['${r.path}|OOP là gì?']);

    expect(() => c.read(vaultProvider.notifier).rename(r.path, 'Tên/không hợp lệ'), throwsA(isA<FormatException>()));
  });
}
