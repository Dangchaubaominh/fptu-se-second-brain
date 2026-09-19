import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_brain/core/vault_index.dart';
import 'package:fptu_brain/core/wikilink_completion.dart';
import 'package:fptu_brain/ui/markdown_editor.dart';

Note note(String path, String content, [int day = 1]) => Note.parse(path, content, DateTime(2026, 1, day));

final index = VaultIndex('/v', [
  note('Courses/PRF192.md', '---\ntype: course\naliases: [Programming Fundamentals]\n---\n', 3),
  note('Concepts/Đệ quy (Recursion).md', '# Đệ quy', 2),
  note('Concepts/Design Patterns.md', '', 1),
  note('Concepts/MVC.md', '', 4),
  note('Archive/MVC.md', '', 5),
]);

void main() {
  group('activeWikilinkQuery', () {
    test('detects an open link on the current line', () {
      const t = 'Xem [[de q';
      final q = activeWikilinkQuery(t, t.length)!;
      expect(q.start, 4);
      expect(q.query, 'de q');
      expect(activeWikilinkQuery('a\n[[', 4)!.query, '');
    });

    test('ignores closed links, alias/heading parts, other lines and inline code', () {
      expect(activeWikilinkQuery('[[MVC]] x', 9), isNull);
      expect(activeWikilinkQuery('[[MVC|mo', 8), isNull);
      expect(activeWikilinkQuery('[[MVC#he', 8), isNull);
      expect(activeWikilinkQuery('[[abc\nxyz', 9), isNull);
      expect(activeWikilinkQuery('`[[abc', 6), isNull);
      expect(activeWikilinkQuery('[', 1), isNull);
    });
  });

  group('suggestLinks', () {
    test('ranks accent-insensitively: exact, prefix, alias, contains', () {
      // Both are prefix matches; the shorter title wins the tie.
      expect(suggestLinks(index, 'de').map((s) => s.note.title), ['Design Patterns', 'Đệ quy (Recursion)']);
      expect(suggestLinks(index, 'recursion').single.note.title, 'Đệ quy (Recursion)');
      final alias = suggestLinks(index, 'programming').single;
      expect(alias.note.path, 'Courses/PRF192.md');
      expect(alias.alias, 'Programming Fundamentals');
      expect(suggestLinks(index, 'zzz'), isEmpty);
    });

    test('empty query lists recent notes and excludes the current one', () {
      final s = suggestLinks(index, '', exclude: 'Archive/MVC.md');
      expect(s.first.note.path, 'Concepts/MVC.md');
      expect(s.any((x) => x.note.path == 'Archive/MVC.md'), isFalse);
    });
  });

  test('linkTarget uses path for duplicate names and appends alias', () {
    final dupe = suggestLinks(index, 'mvc').firstWhere((s) => index.resolve('MVC') != s.note.path);
    expect(linkTarget(index, dupe), dupe.note.path.replaceAll('.md', ''));
    expect(linkTarget(index, suggestLinks(index, 'programming').single), 'PRF192|Programming Fundamentals');
  });

  test('applyWikilinkCompletion closes the link and reuses existing ]]', () {
    const q = WikilinkQuery(4, 'de');
    final r = applyWikilinkCompletion('Xem [[de nhé', 8, q, 'Đệ quy');
    expect(r.text, 'Xem [[Đệ quy]] nhé');
    expect(r.cursor, 'Xem [[Đệ quy]]'.length);
    expect(applyWikilinkCompletion('Xem [[de]]', 8, q, 'MVC').text, 'Xem [[MVC]]');
  });

  group('MarkdownEditor popup', () {
    Future<TextEditingController> pumpEditor(WidgetTester tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: MarkdownEditor(controller: ctrl, onChanged: (_) {}, index: index),
          ),
        ),
      ));
      return ctrl;
    }

    testWidgets('typing [[ shows suggestions, arrows + Enter insert the link', (tester) async {
      final ctrl = await pumpEditor(tester);
      await tester.enterText(find.byType(TextField), 'Xem [[de');
      await tester.pump();
      expect(find.text('Đệ quy (Recursion)'), findsOneWidget);
      expect(find.text('Design Patterns'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(ctrl.text, 'Xem [[Đệ quy (Recursion)]]');
      expect(ctrl.selection.baseOffset, ctrl.text.length);
      expect(find.text('Design Patterns'), findsNothing); // popup closed
    });

    testWidgets('clicking a suggestion inserts it; Esc dismisses', (tester) async {
      final ctrl = await pumpEditor(tester);
      await tester.enterText(find.byType(TextField), '[[prog');
      await tester.pump();
      await tester.tap(find.text('Programming Fundamentals  →  PRF192'));
      await tester.pump();
      expect(ctrl.text, '[[PRF192|Programming Fundamentals]]');

      await tester.enterText(find.byType(TextField), '[[mv');
      await tester.pump();
      expect(find.textContaining('Esc đóng'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.textContaining('Esc đóng'), findsNothing);
      expect(ctrl.text, '[[mv');
    });

    testWidgets('unknown name offers a link to a new note', (tester) async {
      final ctrl = await pumpEditor(tester);
      await tester.enterText(find.byType(TextField), '[[Kiến trúc Clean');
      await tester.pump();
      expect(find.text('Liên kết tới note mới "Kiến trúc Clean"'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ctrl.text, '[[Kiến trúc Clean]]');
    });
  });
}
