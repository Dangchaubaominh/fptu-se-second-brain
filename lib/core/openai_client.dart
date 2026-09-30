import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';

/// A provider that speaks the OpenAI chat-completions protocol.
class AiPreset {
  const AiPreset(this.name, this.baseUrl, this.model, {this.needsKey = true, this.hint = ''});

  final String name;
  final String baseUrl;

  /// A model that exists at the time of writing; the user can type another one.
  final String model;
  final bool needsKey;
  final String hint;

  static const presets = [
    AiPreset(
      'Google Gemini',
      'https://generativelanguage.googleapis.com/v1beta/openai',
      'gemini-2.0-flash',
      hint: 'Lấy key ở aistudio.google.com (dạng AIza…). Có bậc miễn phí.',
    ),
    AiPreset(
      'OpenRouter',
      'https://openrouter.ai/api/v1',
      'meta-llama/llama-3.3-70b-instruct:free',
      hint: 'Một key dùng nhiều model; các model có đuôi :free thì miễn phí.',
    ),
    AiPreset('Groq', 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile', hint: 'Nhanh, có bậc miễn phí.'),
    AiPreset('OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini', hint: 'Key dạng sk-… của platform.openai.com.'),
    AiPreset(
      'Ollama (máy của bạn)',
      'http://localhost:11434/v1',
      'llama3.1',
      needsKey: false,
      hint: 'Chạy offline. Cần cài Ollama và tải model trước: ollama pull llama3.1',
    ),
  ];
}

/// Client for any OpenAI-compatible endpoint.
///
/// Unlike Claude these services don't share one structured-output format, so
/// JSON requests ask for `json_object` and put the schema in the prompt; the
/// reply is parsed leniently and reported clearly when it isn't valid JSON.
class OpenAiCompatibleClient implements AiClient {
  OpenAiCompatibleClient({
    required this.apiKey,
    required String baseUrl,
    required this.model,
    this.providerName = 'Model',
    http.Client? client,
  }) : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
       _http = client ?? http.Client();

  final String apiKey;
  final String baseUrl;
  final String model;
  final String providerName;
  final http.Client _http;

  @override
  String get label => '$providerName ($model)';

  Uri get _endpoint => Uri.parse('$baseUrl/chat/completions');

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey',
  };

  Map<String, dynamic> _body(String system, List<ChatMessage> messages, int maxTokens) => {
    'model': model,
    'max_tokens': maxTokens,
    'messages': [
      {'role': 'system', 'content': system},
      for (final m in messages) {'role': m.role, 'content': m.content},
    ],
  };

  @override
  Stream<String> streamText({
    required String system,
    required List<ChatMessage> messages,
    int maxTokens = 8000,
    bool cacheSystem = false, // Anthropic-only; ignored here.
  }) async* {
    final req = http.Request('POST', _endpoint)
      ..headers.addAll(_headers)
      ..body = jsonEncode({..._body(system, messages, maxTokens), 'stream': true});
    final res = await _http.send(req);
    if (res.statusCode != 200) {
      throw AiException(describeHttpError(res.statusCode, await res.stream.bytesToString(), providerName));
    }
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload == '[DONE]') return;
      final Map<String, dynamic> data;
      try {
        data = jsonDecode(payload) as Map<String, dynamic>;
      } on FormatException {
        continue; // keep-alive or comment line
      }
      if (data['error'] != null) throw AiException('Lỗi từ $providerName: ${data['error']}');
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) continue;
      final choice = choices.first as Map<String, dynamic>;
      final delta = choice['delta'] as Map<String, dynamic>?;
      final chunk = delta?['content'];
      if (chunk is String && chunk.isNotEmpty) yield chunk;
      if (choice['finish_reason'] == 'length') yield '\n\n_(Câu trả lời bị cắt do quá dài.)_';
    }
  }

  @override
  Future<Map<String, dynamic>> completeJson({
    required String system,
    required List<ChatMessage> messages,
    required Map<String, dynamic> schema,
    int maxTokens = 8000,
    bool cacheSystem = false,
  }) async {
    final withSchema = [
      ...messages.take(messages.length - 1),
      (
        role: messages.last.role,
        content:
            '${messages.last.content}\n\n'
            'Chỉ trả về JSON hợp lệ theo đúng schema sau, không thêm chữ nào khác:\n'
            '${jsonEncode(schema)}',
      ),
    ];
    final res = await _http.post(
      _endpoint,
      headers: _headers,
      body: jsonEncode({
        ..._body(system, withSchema, maxTokens),
        'response_format': {'type': 'json_object'},
      }),
    );
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) throw AiException(describeHttpError(res.statusCode, text, providerName));
    final body = jsonDecode(text) as Map<String, dynamic>;
    final choices = body['choices'] as List?;
    if (choices == null || choices.isEmpty) throw AiException('$providerName không trả về nội dung nào.');
    final content = (choices.first as Map<String, dynamic>)['message']?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw AiException('$providerName không trả về nội dung nào.');
    }
    return decodeJsonObject(content, provider: providerName);
  }

  @override
  void close() => _http.close();
}
