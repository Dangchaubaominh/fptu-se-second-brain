import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_brain/core/flashcards.dart';
import 'package:fptu_brain/core/markdown_utils.dart';
import 'package:fptu_brain/core/sample_vault.dart';
import 'package:fptu_brain/core/vault_index.dart';
import 'package:fptu_brain/core/vault_repository.dart';

Note note(String path, String content) => Note.parse(path, content, DateTime(2026));

void main() {
  group('markdown_utils', () {
    test('parses wikilinks with alias, heading, embed and ignores code', () {
      final links = parseWikiLinks(
        'See [[PRF192]], [[OOP#Kế thừa|kế thừa]] and ![[img.png]]\n```\n[[NotALink]]\n``` `[[nope]]`',
      );
      expect(links.map((l) => l.target), ['PRF192', 'OOP', 'img.png']);
      expect(links[1].heading, 'Kế thừa');
      expect(links[1].alias, 'kế thừa');
      expect(links[2].embed, isTrue);
    });

    test('parses inline tags but not headings or numbers', () {
      expect(parseInlineTags('# Heading\nText #java #ky3/oop #123 and C#'), {'java', 'ky3/oop'});
    });

    test('frontmatter split and field update preserves other lines', () {
      const src = '---\ntype: course\nstatus: todo\ntags: [a, b]\n---\n# Body\n';
      final fm = splitFrontmatter(src);
      expect(fm.data['type'], 'course');
      expect(fm.data['tags'], ['a', 'b']);
      expect(fm.body, '# Body\n');

      final updated = setFrontmatterField(src, 'status', 'done');
      expect(splitFrontmatter(updated).data['status'], 'done');
      expect(updated, contains('tags: [a, b]'));
      expect(splitFrontmatter(setFrontmatterField(src, 'semester', '3')).data['semester'], 3);
      expect(setFrontmatterField('# x', 'status', 'done'), startsWith('---\nstatus: done\n---\n'));
    });

    test('converts wikilinks and callouts for preview', () {
      final md = obsidianToMarkdown('[[Con trỏ (Pointer)|con trỏ]]\n> [!info] Kỳ 1\n> text');
      expect(md, contains('[con trỏ](wikilink:Con%20tr%E1%BB%8F%20(Pointer))'));
      expect(md, contains('**ℹ️ Kỳ 1**'));
    });

    test('folds Vietnamese diacritics keeping length', () {
      const s = 'Cây Nhị Phân Đệ Quy';
      expect(foldVietnamese(s), 'cay nhi phan de quy');
      expect(foldVietnamese(s).length, s.length);
    });
  });

  group('VaultIndex', () {
    final index = VaultIndex('/v', [
      note(
        'Courses/PRF192.md',
        '---\ntype: course\ncode: PRF192\nsemester: 1\naliases: [Programming Fundamentals]\n---\n[[Con trỏ]]',
      ),
      note('Concepts/Con trỏ.md', 'Học ở [[prf192]] và [[Programming Fundamentals]]. #c'),
      note('Home.md', '[[Courses/PRF192]] [[Missing]]'),
    ]);

    test('resolves by name, path and alias, case-insensitively', () {
      expect(index.resolve('PRF192'), 'Courses/PRF192.md');
      expect(index.resolve('courses/prf192.md'), 'Courses/PRF192.md');
      expect(index.resolve('programming fundamentals'), 'Courses/PRF192.md');
      expect(index.resolve('Missing'), isNull);
    });

    test('builds backlinks', () {
      expect(index.backlinks['Courses/PRF192.md'], {'Concepts/Con trỏ.md', 'Home.md'});
      expect(index.courses.single.semester, 1);
    });

    test('search is accent-insensitive and supports tags', () {
      expect(index.search('con tro').first.note.path, 'Concepts/Con trỏ.md');
      expect(index.search('#c').single.note.path, 'Concepts/Con trỏ.md');
    });
  });

  group('flashcards', () {
    test('parses Q::A lines, skips code, lists, tables and :::', () {
      final n = note('a.md', 'Q1::A1\n- list::no\n| t::no |\n```\nstd::cout\n```\nQ2 ::: no\nQ3?:: A3');
      expect(parseFlashcards(n).map((c) => '${c.question}|${c.answer}'), ['Q1|A1', 'Q3?|A3']);
    });

    test('formatFlashcard keeps one line', () {
      expect(formatFlashcard('a\nb', 'x::y'), 'a b::x:y');
    });

    test('SM-2 schedule grows interval and resets on again', () {
      final now = DateTime(2026, 9, 1, 9);
      var s = schedule(const CardState(), Grade.good, now);
      expect(s.interval, 1);
      s = schedule(s, Grade.good, now);
      expect(s.interval, 3);
      s = schedule(s, Grade.good, now);
      expect(s.interval, 8); // 3 * 2.5 rounded
      final again = schedule(s, Grade.again, now);
      expect(again.reps, 0);
      expect(again.isDue(now.add(const Duration(minutes: 11))), isTrue);
      expect(CardState.fromJson(s.toJson()).interval, s.interval);
    });
  });

  test('sample vault is created and fully linked', () async {
    final dir = await Directory.systemTemp.createTemp('fptu_vault');
    try {
      await SampleVault.create(dir.path);
      final repo = VaultRepository(dir.path);
      final index = VaultIndex(dir.path, await repo.loadAll());
      expect(index.courses.length, greaterThan(35));
      final unresolved = [
        for (final n in index.notes.values)
          for (final l in n.links)
            if (index.resolve(l.target) == null) '${n.path} -> ${l.target}',
      ];
      expect(unresolved, isEmpty);
      expect(allFlashcards(index).length, greaterThan(25));

      final created = await repo.createNote('Concepts', 'MVC');
      expect(created.path, 'Concepts/MVC 1.md');
      await repo.saveSrs({'x': const CardState(interval: 3)});
      expect((await repo.loadSrs())['x']!.interval, 3);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
