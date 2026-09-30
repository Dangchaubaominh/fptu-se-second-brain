import 'dart:convert';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef ChatMessage = ({String role, String content});

/// What the app needs from a chat model, so Claude and any OpenAI-compatible
/// service (Gemini, OpenRouter, Groq, OpenAI, a local Ollama) are interchangeable.
abstract class AiClient {
  /// Name shown in the UI, e.g. "Claude (claude-opus-5)".
  String get label;

  /// How much vault text to put in one request. Claude takes the whole vault;
  /// smaller models (and free tiers) fail or time out on prompts that big.
  int get contextCharBudget;

  /// Streams the answer in pieces, so long replies appear as they are written.
  Stream<String> streamText({
    required String system,
    required List<ChatMessage> messages,
    int maxTokens,

    /// Anthropic-only: cache the system prompt. Other providers ignore it.
    bool cacheSystem,
  });

  /// One call that must return JSON matching [schema] (flashcards, quizzes).
  Future<Map<String, dynamic>> completeJson({
    required String system,
    required List<ChatMessage> messages,
    required Map<String, dynamic> schema,
    int maxTokens,
    bool cacheSystem,
  });

  void close();
}

/// Models sometimes wrap JSON in ``` fences or add a sentence around it.
Map<String, dynamic> decodeJsonObject(String raw, {String? provider}) {
  var text = raw.trim();
  final fence = RegExp(r'^```[a-zA-Z]*\s*|\s*```$');
  text = text.replaceAll(fence, '').trim();
  if (!text.startsWith('{')) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) text = text.substring(start, end + 1);
  }
  try {
    final value = jsonDecode(text);
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('không phải JSON object');
  } on FormatException {
    throw AiException(
      '${provider ?? 'Model'} trả về dữ liệu không đúng định dạng JSON. '
      'Hãy thử lại, hoặc chọn model mạnh hơn trong Cài đặt.',
    );
  }
}

/// Transient failures worth retrying: rate limits and server overload.
bool isRetryableStatus(int status) => status == 429 || status == 500 || status == 502 || status == 503 || status == 504;

String describeHttpError(int status, String body, String provider) {
  String? apiMsg;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['error'] is Map) apiMsg = (decoded['error'] as Map)['message']?.toString();
  } catch (_) {}
  final hint = switch (status) {
    400 => 'Yêu cầu không hợp lệ (có thể tên model sai).',
    401 || 403 => 'API key không hợp lệ hoặc không có quyền dùng model này. Kiểm tra lại trong Cài đặt.',
    404 =>
      'Không tìm thấy endpoint hoặc model. Kiểm tra địa chỉ API và tên model '
          '(tên model cũ hay bị nhà cung cấp ngừng hỗ trợ).',
    429 => 'Vượt giới hạn tốc độ, thử lại sau ít phút.',
    503 =>
      '$provider đang quá tải (đã thử lại vài lần). Chờ một lát rồi thử lại, '
          'hoặc hỏi theo phạm vi một môn thay vì toàn bộ vault.',
    >= 500 => 'Máy chủ $provider đang lỗi hoặc quá tải, thử lại sau.',
    _ => 'Yêu cầu thất bại.',
  };
  return '$hint (HTTP $status${apiMsg != null ? ': $apiMsg' : ''})';
}
