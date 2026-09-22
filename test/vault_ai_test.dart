import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_brain/core/ai_assistant.dart';
import 'package:fptu_brain/core/claude_client.dart';
import 'package:fptu_brain/core/vault_ai.dart';
import 'package:fptu_brain/core/vault_index.dart';
import 'package:fptu_brain/state/providers.dart';
import 'package:fptu_brain/ui/ask_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Note note(String path, String content) => Note.parse(path, content, DateTime(2026));

final index = VaultIndex('/v/My Vault', [
  note('Courses/CSD201.md', '---\ntype: course\ncode: CSD201\nname: DSA\n---\n[[BST]] [[Big-O]]'),
  note('Concepts/BST.md', 'Cây nhị phân tìm kiếm, duyệt in-order cho dãy tăng dần.'),
  note('Concepts/Big-O.md', 'Binary search là O(log n).'),
  note('Concepts/OOP.md', 'Đóng gói, kế thừa, đa hình, trừu tượng. ${'x' * 300}'),
  note('Home.md', '- [[CSD201]]'),
]);

const quizJson = {
  'questions': [
    {
      'question': 'Duyệt BST theo thứ tự nào cho dãy tăng dần?',
      'options': ['Pre-order', 'In-order', 'Post-order', 'Level-order'],
      'answer_index': 1,
      'explanation': 'In-order thăm trái - gốc - phải.',
      'source': 'BST',
    },
    {
      'question': 'Độ phức tạp của binary search?',
      'options': ['O(n)', 'O(1)', 'O(log n)', 'O(n log n)'],
      'answer_index': 2,
      'explanation': 'Mỗi bước loại một nửa.',
      'source': 'Big-O',
    },
    {
      'question': 'Câu lỗi',
      'options': ['A'],
      'answer_index': 3,
      'explanation': '',
      'source': '',
    },
  ],
};

void main() {
  group('buildVaultContext', () {
    test('whole vault includes every note', () {
      final ctx = buildVaultContext(index);
      expect(ctx.included.length, 5);
      expect(ctx.omitted, isEmpty);
      expect(ctx.label, 'Toàn bộ vault "My Vault"');
      expect(ctx.text, contains('<note path="Concepts/BST.md" title="BST">'));
    });

    test('course scope = course note + links + backlinks', () {
      final ctx = buildVaultContext(index, coursePath: 'Courses/CSD201.md');
      expect(ctx.label, 'CSD201 — DSA');
      expect(ctx.included, ['Courses/CSD201.md', 'Concepts/BST.md', 'Concepts/Big-O.md', 'Home.md']);
    });

    test('over budget keeps the most relevant notes and reports the rest', () {
      final ctx = buildVaultContext(index, question: 'binary search log', maxChars: 400);
      expect(ctx.included.first, 'Concepts/Big-O.md');
      expect(ctx.omitted, contains('Concepts/OOP.md'));
      expect(ctx.included.length + ctx.omitted.length, 5);
    });
  });

  test('quiz parsing drops malformed questions and exports to Markdown', () {
    final quiz = QuizQuestion.listFromJson(quizJson);
    expect(quiz.length, 2);
    expect(quiz.first.source, 'BST');
    final md = quizToMarkdown('CSD201 — DSA', quiz, at: DateTime(2026, 9, 22, 8, 5), answers: [1, 0]);
    expect(md, contains('type: quiz'));
    expect(md, contains('score: 1/2'));
    expect(md, contains('## Câu 1. Duyệt BST'));
    expect(md, contains('- B. In-order'));
    expect(md, contains('> [!success]- Đáp án: B'));
    expect(md, contains('> Nguồn: [[BST]]'));
  });

  test('generateQuiz sends the vault as a cached system prompt with a JSON schema', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': jsonEncode(quizJson)},
            ],
            'stop_reason': 'end_turn',
          }),
        ),
        200,
      );
    });
    final ai = AiAssistant(ClaudeClient('test-key', client: client));
    final quiz = await ai.generateQuiz(buildVaultContext(index, coursePath: 'Courses/CSD201.md'), count: 2);
    expect(quiz.length, 2);
    final system = (sent['system'] as List).single as Map<String, dynamic>;
    expect(system['cache_control'], {'type': 'ephemeral'});
    expect(system['text'], contains('<vault>'));
    expect(sent['output_config']['format']['type'], 'json_schema');
    expect(sent['model'], ClaudeClient.model);
  });

  testWidgets('Ask page: generate a quiz, answer, submit and see the score', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': jsonEncode(quizJson)},
            ],
            'stop_reason': 'end_turn',
          }),
        ),
        200,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultProvider.overrideWith(_FakeVault.new),
          aiProvider.overrideWithValue(AiAssistant(ClaudeClient('k', client: client))),
        ],
        child: const MaterialApp(home: Scaffold(body: AskPage())),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Trắc nghiệm'));
    await tester.pump();
    await tester.tap(find.text('Tạo đề'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Duyệt BST theo thứ tự nào'), findsOneWidget);

    await tester.tap(find.text('B. In-order')); // right
    await tester.tap(find.text('A. O(n)')); // wrong
    await tester.pump();
    await tester.tap(find.textContaining('Nộp bài (2/2 câu)'));
    await tester.pump();
    expect(find.text('Điểm: 1/2'), findsOneWidget);
    expect(find.textContaining('Đáp án: C. Mỗi bước loại một nửa.'), findsOneWidget);
  });
}

class _FakeVault extends VaultNotifier {
  @override
  Future<VaultIndex?> build() async => index;
}
