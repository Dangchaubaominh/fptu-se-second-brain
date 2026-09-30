import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_brain/core/ai_client.dart';
import 'package:fptu_brain/core/openai_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Server-sent events exactly as an OpenAI-compatible endpoint sends them.
String _sse(List<String> chunks, {String? finish}) => [
  for (final c in chunks)
    'data: ${jsonEncode({
      'choices': [
        {
          'delta': {'content': c},
        },
      ],
    })}\n',
  if (finish != null)
    'data: ${jsonEncode({
      'choices': [
        {'delta': <String, dynamic>{}, 'finish_reason': finish},
      ],
    })}\n',
  'data: [DONE]\n',
].join();

http.Response _resp(String body, [int code = 200]) => http.Response.bytes(utf8.encode(body), code);

OpenAiCompatibleClient _client(MockClient mock) => OpenAiCompatibleClient(
  apiKey: 'k-test',
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  model: 'gemini-2.0-flash',
  providerName: 'Google Gemini',
  client: mock,
);

void main() {
  test('label and endpoint (trailing slash in the base URL is ignored)', () {
    late Uri url;
    final c = _client(
      MockClient((req) async {
        url = req.url;
        return _resp('{}', 500);
      }),
    );
    expect(c.label, 'Google Gemini (gemini-2.0-flash)');
    expect(
      () => c.completeJson(system: 's', messages: [(role: 'user', content: 'x')], schema: const {}),
      throwsA(isA<AiException>()),
    );
    // The request is sent lazily, so wait a tick before checking the URL.
    return Future(() {
      expect(url.toString(), 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions');
    });
  });

  test('streams text deltas and stops at [DONE]', () async {
    late Map<String, dynamic> sent;
    final c = _client(
      MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.headers['authorization'], 'Bearer k-test');
        return _resp(_sse(['Xin ', 'chào ', 'bạn']));
      }),
    );
    final out = await c.streamText(system: 'sys', messages: [(role: 'user', content: 'hi')]).join();
    expect(out, 'Xin chào bạn');
    expect(sent['stream'], isTrue);
    expect(sent['model'], 'gemini-2.0-flash');
    expect((sent['messages'] as List).first, {'role': 'system', 'content': 'sys'});
  });

  test('warns when the answer was cut off', () async {
    final c = _client(MockClient((_) async => _resp(_sse(['một nửa'], finish: 'length'))));
    expect(await c.streamText(system: '', messages: [(role: 'user', content: 'x')]).join(), contains('bị cắt'));
  });

  test('completeJson asks for JSON, inlines the schema and parses fenced output', () async {
    late Map<String, dynamic> sent;
    final c = _client(
      MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '```json\n{"cards":[{"question":"Q","answer":"A"}]}\n```'},
                },
              ],
            }),
          ),
          200,
        );
      }),
    );
    final json = await c.completeJson(
      system: 'sys',
      messages: [(role: 'user', content: 'Tạo thẻ')],
      schema: const {'type': 'object'},
    );
    expect(json['cards'], [
      {'question': 'Q', 'answer': 'A'},
    ]);
    expect(sent['response_format'], {'type': 'json_object'});
    expect((sent['messages'] as List).last['content'], contains('"type":"object"'));
  });

  test('reports a clear error when the model does not return JSON', () async {
    final c = _client(
      MockClient(
        (_) async => _resp(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Xin lỗi, tôi không thể.'},
              },
            ],
          }),
        ),
      ),
    );
    expect(
      () => c.completeJson(system: '', messages: [(role: 'user', content: 'x')], schema: const {}),
      throwsA(isA<AiException>().having((e) => e.message, 'message', contains('không đúng định dạng JSON'))),
    );
  });

  test('HTTP errors explain what to check', () async {
    final c = _client(
      MockClient(
        (_) async => _resp(
          jsonEncode({
            'error': {'message': 'API key not valid'},
          }),
          401,
        ),
      ),
    );
    await expectLater(
      c.streamText(system: '', messages: [(role: 'user', content: 'x')]).join(),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          allOf(contains('API key'), contains('API key not valid')),
        ),
      ),
    );
    final notFound = _client(MockClient((_) async => _resp('{}', 404)));
    await expectLater(
      notFound.streamText(system: '', messages: [(role: 'user', content: 'x')]).join(),
      throwsA(isA<AiException>().having((e) => e.message, 'message', contains('tên model'))),
    );
  });

  test('no key means no Authorization header (Ollama)', () async {
    final ollama = OpenAiCompatibleClient(
      apiKey: '',
      baseUrl: 'http://localhost:11434/v1',
      model: 'llama3.1',
      client: MockClient((req) async {
        expect(req.headers.containsKey('authorization'), isFalse);
        return _resp(_sse(['ok']));
      }),
    );
    expect(await ollama.streamText(system: '', messages: [(role: 'user', content: 'x')]).join(), 'ok');
  });
}
