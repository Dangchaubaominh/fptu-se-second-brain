import 'dart:convert';

import 'package:http/http.dart' as http;

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef ChatMessage = ({String role, String content});

/// Minimal Claude Messages API client over raw HTTP (there is no official Dart SDK).
class ClaudeClient {
  ClaudeClient(this.apiKey, {http.Client? client}) : _http = client ?? http.Client();

  static const model = 'claude-opus-5';
  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  final String apiKey;
  final http.Client _http;

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
    // If the model declines a request, the API retries it on a recommended fallback model.
    'anthropic-beta': 'server-side-fallback-2026-07-01',
  };

  Map<String, dynamic> _body(String system, List<ChatMessage> messages, int maxTokens) => {
    'model': model,
    'max_tokens': maxTokens,
    'fallbacks': 'default',
    'system': system,
    'messages': [
      for (final m in messages) {'role': m.role, 'content': m.content},
    ],
  };

  /// Streams text deltas. Used for summaries and chat so long answers
  /// render progressively and don't hit HTTP timeouts.
  Stream<String> streamText({
    required String system,
    required List<ChatMessage> messages,
    int maxTokens = 64000,
  }) async* {
    final req = http.Request('POST', _endpoint)
      ..headers.addAll(_headers)
      ..body = jsonEncode({..._body(system, messages, maxTokens), 'stream': true});
    final res = await _http.send(req);
    if (res.statusCode != 200) {
      throw AiException(_describeError(res.statusCode, await res.stream.bytesToString()));
    }
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
      switch (data['type']) {
        case 'content_block_delta':
          final delta = data['delta'] as Map<String, dynamic>;
          if (delta['type'] == 'text_delta') yield delta['text'] as String;
        case 'message_delta':
          final stop = (data['delta'] as Map<String, dynamic>)['stop_reason'];
          if (stop == 'refusal') throw AiException('Claude đã từ chối yêu cầu này.');
          if (stop == 'max_tokens') yield '\n\n_(Câu trả lời bị cắt do quá dài.)_';
        case 'error':
          throw AiException('Lỗi từ API: ${(data['error'] as Map?)?['message'] ?? data}');
      }
    }
  }

  /// Non-streaming call constrained to a JSON schema (structured outputs).
  Future<Map<String, dynamic>> completeJson({
    required String system,
    required List<ChatMessage> messages,
    required Map<String, dynamic> schema,
    int maxTokens = 16000,
  }) async {
    final res = await _http.post(
      _endpoint,
      headers: _headers,
      body: jsonEncode({
        ..._body(system, messages, maxTokens),
        'output_config': {
          'format': {'type': 'json_schema', 'schema': schema},
        },
      }),
    );
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) throw AiException(_describeError(res.statusCode, text));
    final msg = jsonDecode(text) as Map<String, dynamic>;
    if (msg['stop_reason'] == 'refusal') throw AiException('Claude đã từ chối yêu cầu này.');
    if (msg['stop_reason'] == 'max_tokens') throw AiException('Phản hồi quá dài, hãy thử với ghi chú ngắn hơn.');
    final out = (msg['content'] as List)
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    return jsonDecode(out) as Map<String, dynamic>;
  }

  static String _describeError(int status, String body) {
    String? apiMsg;
    try {
      apiMsg = ((jsonDecode(body) as Map)['error'] as Map?)?['message'] as String?;
    } catch (_) {}
    final hint = switch (status) {
      401 => 'API key không hợp lệ. Kiểm tra lại trong Cài đặt.',
      403 => 'API key không có quyền dùng model này.',
      429 => 'Vượt giới hạn tốc độ, thử lại sau ít phút.',
      >= 500 => 'Máy chủ Anthropic đang lỗi hoặc quá tải, thử lại sau.',
      _ => 'Yêu cầu không hợp lệ.',
    };
    return '$hint (HTTP $status${apiMsg != null ? ': $apiMsg' : ''})';
  }

  void close() => _http.close();
}
