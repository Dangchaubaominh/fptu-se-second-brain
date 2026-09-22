import 'claude_client.dart';
import 'vault_index.dart';

const _system = '''
Bạn là trợ lý học tập cho sinh viên ngành Kỹ thuật phần mềm (Software Engineering) tại Đại học FPT.
Người dùng lưu kiến thức trong một Obsidian vault ("second brain").
Luôn trả lời bằng tiếng Việt; giữ nguyên thuật ngữ tiếng Anh chuyên ngành khi cần.
Định dạng bằng Markdown tương thích Obsidian. Khi nhắc tới khái niệm nên có note riêng, viết dưới dạng [[Tên khái niệm]].''';

/// Note-aware prompts on top of [ClaudeClient].
class AiAssistant {
  AiAssistant(this.client);
  final ClaudeClient client;

  static String noteContext(Note note, VaultIndex index) {
    final related = {
      ...?index.outgoing[note.path],
      ...?index.backlinks[note.path],
    }.map((p) => index.notes[p]?.title).whereType<String>().toList();
    return '<note title="${note.title}" path="${note.path}">\n${note.content}\n</note>\n'
        '${related.isEmpty ? '' : 'Các note liên quan trong vault: ${related.map((t) => '[[$t]]').join(', ')}\n'}';
  }

  Stream<String> summarize(Note note, VaultIndex index) => client.streamText(
    system: _system,
    messages: [
      (
        role: 'user',
        content:
            '${noteContext(note, index)}\n'
            'Tóm tắt ghi chú trên cho việc ôn thi: 3–7 gạch đầu dòng ý chính, '
            'sau đó mục "Khái niệm then chốt" liệt kê các khái niệm dạng [[wikilink]]. '
            'Chỉ trả về phần tóm tắt, không mở đầu hay kết luận.',
      ),
    ],
  );

  Future<List<({String question, String answer})>> generateFlashcards(
    Note note,
    VaultIndex index, {
    int count = 8,
  }) async {
    final json = await client.completeJson(
      system: _system,
      messages: [
        (
          role: 'user',
          content:
              '${noteContext(note, index)}\n'
              'Tạo tối đa $count flashcard giúp ôn tập nội dung ghi chú trên (kiểu câu hỏi thi FE của FPTU). '
              'Mỗi câu hỏi rõ ràng, tự đứng được; câu trả lời ngắn gọn trong một dòng. '
              'Không trùng với các dòng "Câu hỏi::Trả lời" đã có trong note.',
        ),
      ],
      schema: {
        'type': 'object',
        'properties': {
          'cards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'question': {'type': 'string'},
                'answer': {'type': 'string'},
              },
              'required': ['question', 'answer'],
              'additionalProperties': false,
            },
          },
        },
        'required': ['cards'],
        'additionalProperties': false,
      },
    );
    return [
      for (final c in (json['cards'] as List).cast<Map<String, dynamic>>())
        (question: c['question'] as String, answer: c['answer'] as String),
    ];
  }

  Stream<String> chat(Note note, VaultIndex index, List<ChatMessage> history) => client.streamText(
    system:
        '$_system\n\nNgười dùng đang mở ghi chú sau, hãy dựa vào nó khi trả lời '
        '(có thể bổ sung kiến thức ngoài nếu cần, nhưng nói rõ phần nào không có trong note):\n'
        '${noteContext(note, index)}',
    messages: history,
  );
}
