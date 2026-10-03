import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_brain/core/ai_assistant.dart';
import 'package:fptu_brain/core/claude_client.dart';
import 'package:fptu_brain/core/vault_index.dart';
import 'package:fptu_brain/state/providers.dart';
import 'package:fptu_brain/ui/ask_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final index = VaultIndex('/v/My Vault', [
  Note.parse('Courses/CSD201.md', '---\ntype: course\ncode: CSD201\nname: DSA\n---\n[[BST]]', DateTime(2026)),
  Note.parse('Concepts/BST.md', 'Cây nhị phân tìm kiếm.', DateTime(2026)),
]);

class _FakeVault extends VaultNotifier {
  @override
  Future<VaultIndex?> build() async => index;
}

Future<void> _pumpAskPage(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = MockClient(
    (_) async => http.Response.bytes(
      utf8.encode('data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}\n'),
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
}

void main() {
  // The question box used to be a thin underlined field at the very bottom, and
  // users thought the example chips were the only way to ask something.
  for (final size in const [Size(1600, 1000), Size(1100, 700)]) {
    testWidgets('question box is visible and accepts a typed question at $size', (tester) async {
      await _pumpAskPage(tester, size);

      expect(find.text('Nhập câu hỏi của bạn ở ô bên dưới'), findsOneWidget);
      final box = find.widgetWithText(TextField, 'Nhập câu hỏi của bạn về ghi chú…');
      expect(box, findsOneWidget);

      final rect = tester.getRect(box);
      expect(rect.height, greaterThan(40), reason: 'ô nhập phải đủ cao để nhìn thấy rõ');
      expect(rect.bottom, lessThanOrEqualTo(size.height), reason: 'ô nhập không được nằm ngoài màn hình');

      await tester.enterText(box, 'Câu hỏi của riêng em');
      await tester.pump();
      expect(find.text('Câu hỏi của riêng em'), findsOneWidget);
    });
  }

  testWidgets('typing a question and pressing the send button starts a request', (tester) async {
    await _pumpAskPage(tester, const Size(1400, 900));
    await tester.enterText(find.widgetWithText(TextField, 'Nhập câu hỏi của bạn về ghi chú…'), 'BST là gì?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    // The question appears in the conversation and the input is cleared.
    expect(find.text('BST là gì?'), findsOneWidget);
    expect(find.text('Nhập câu hỏi của bạn ở ô bên dưới'), findsNothing);
  });
}
