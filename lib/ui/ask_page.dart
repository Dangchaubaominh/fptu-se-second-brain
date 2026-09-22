import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/claude_client.dart';
import '../core/vault_ai.dart';
import '../core/vault_index.dart';
import '../state/providers.dart';
import 'note_preview.dart';
import 'widgets.dart';

enum _Mode { chat, quiz }

/// Ask Claude about the whole vault or one course, or generate an FE-style quiz.
class AskPage extends ConsumerStatefulWidget {
  const AskPage({super.key});

  @override
  ConsumerState<AskPage> createState() => _AskPageState();
}

class _AskPageState extends ConsumerState<AskPage> {
  String? _coursePath; // null = whole vault
  _Mode _mode = _Mode.chat;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _chat = [];
  VaultContext? _chatContext;
  StreamSubscription<String>? _sub;
  String? _busy;
  String? _error;

  int _quizCount = 10;
  List<QuizQuestion>? _quiz;
  VaultContext? _quizContext;
  List<int?> _answers = const [];
  bool _submitted = false;

  // Memoized scope preview; rebuilding the context on every streamed chunk would be wasteful.
  (VaultIndex, String?, VaultContext)? _preview;

  VaultContext _previewFor(VaultIndex index) {
    final cached = _preview;
    if (cached != null && identical(cached.$1, index) && cached.$2 == _coursePath) return cached.$3;
    final ctx = buildVaultContext(index, coursePath: _coursePath);
    _preview = (index, _coursePath, ctx);
    return ctx;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  void _setScope(String? path) {
    _sub?.cancel();
    setState(() {
      _coursePath = path;
      _chat.clear();
      _chatContext = null;
      _quiz = null;
      _busy = null;
      _error = null;
    });
  }

  void _send(VaultIndex index) {
    final ai = ref.read(aiProvider);
    final text = _input.text.trim();
    if (ai == null || text.isEmpty || _busy != null) return;
    _input.clear();
    // Keep the same context for the whole conversation so the prompt cache is reused.
    final ctx = _chatContext ??= buildVaultContext(index, coursePath: _coursePath, question: text);
    _chat.add((role: 'user', content: text));
    final history = List<ChatMessage>.of(_chat);
    _chat.add((role: 'assistant', content: ''));
    setState(() {
      _busy = 'Claude đang đọc ${ctx.included.length} ghi chú…';
      _error = null;
    });
    _scrollToEnd();
    _sub = ai
        .askVault(ctx, history)
        .listen(
          (chunk) {
            setState(() {
              final last = _chat.removeLast();
              _chat.add((role: 'assistant', content: last.content + chunk));
            });
            _scrollToEnd();
          },
          onError: (Object e) => setState(() {
            _error = '$e';
            _busy = null;
            if (_chat.isNotEmpty && _chat.last.content.isEmpty) _chat.removeLast();
          }),
          onDone: () => setState(() => _busy = null),
          cancelOnError: true,
        );
  }

  Future<void> _makeQuiz(VaultIndex index) async {
    final ai = ref.read(aiProvider);
    if (ai == null) return;
    final ctx = buildVaultContext(index, coursePath: _coursePath);
    setState(() {
      _busy = 'Đang soạn $_quizCount câu từ ${ctx.included.length} ghi chú…';
      _error = null;
      _quiz = null;
    });
    try {
      final quiz = await ai.generateQuiz(ctx, count: _quizCount);
      if (!mounted) return;
      if (quiz.isEmpty) throw AiException('Không nhận được câu hỏi hợp lệ, hãy thử lại.');
      setState(() {
        _quiz = quiz;
        _quizContext = ctx;
        _answers = List.filled(quiz.length, null);
        _submitted = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _saveQuiz() async {
    final quiz = _quiz;
    final ctx = _quizContext;
    if (quiz == null || ctx == null) return;
    final index = ref.read(vaultProvider).value!;
    final scope = _coursePath == null ? 'Vault' : index.notes[_coursePath]!.courseCode;
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final note = await ref
        .read(vaultProvider.notifier)
        .create(
          'Quizzes',
          'Đề $scope $stamp',
          content: quizToMarkdown(ctx.label, quiz, at: now, answers: _submitted ? _answers : null),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã lưu vào ${note.path}'),
          action: SnackBarAction(label: 'Mở', onPressed: () => openNote(ref, note.path)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(vaultProvider).value;
    if (index == null) return const SizedBox();
    final ai = ref.watch(aiProvider);
    final theme = Theme.of(context);
    final courses = index.courses;
    final preview = _previewFor(index);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Hỏi AI trên vault',
          subtitle: 'Claude đọc ghi chú của bạn, trả lời kèm nguồn [[note]] và soạn đề trắc nghiệm kiểu FE.',
          actions: [
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.chat, icon: Icon(Icons.forum_outlined), label: Text('Hỏi đáp')),
                ButtonSegment(value: _Mode.quiz, icon: Icon(Icons.quiz_outlined), label: Text('Trắc nghiệm')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Phạm vi:'),
              // Width is capped: some course names are very long.
              SizedBox(
                width: 380,
                child: DropdownButton<String?>(
                  value: _coursePath,
                  isExpanded: true,
                  onChanged: _busy == null ? _setScope : null,
                  items: [
                    DropdownMenuItem(value: null, child: Text('Toàn bộ vault (${index.notes.length} note)')),
                    for (final c in courses)
                      DropdownMenuItem(
                        value: c.path,
                        child: Text('${c.courseCode} — ${c.courseName}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
              Text(
                '${preview.included.length} note · ≈${(preview.text.length / 1000).toStringAsFixed(0)} nghìn ký tự',
                style: theme.textTheme.bodySmall,
              ),
              if (preview.omitted.isNotEmpty)
                Tooltip(
                  message: preview.omitted.take(20).join('\n'),
                  child: Chip(
                    avatar: const Icon(Icons.warning_amber, size: 16),
                    label: Text('${preview.omitted.length} note quá giới hạn sẽ không được gửi'),
                  ),
                ),
            ],
          ),
        ),
        if (_busy != null) ...[const SizedBox(height: 8), const LinearProgressIndicator()],
        if (_error != null)
          Container(
            margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: ai == null
              ? EmptyState(
                  icon: Icons.key_outlined,
                  title: 'Chưa có Claude API key',
                  message: 'Nhập API key trong Cài đặt để hỏi AI trên vault.',
                  action: FilledButton(
                    onPressed: () => ref.read(pageProvider.notifier).set(AppPage.settings),
                    child: const Text('Mở Cài đặt'),
                  ),
                )
              : _mode == _Mode.chat
              ? _buildChat(index, theme)
              : _buildQuiz(index, theme),
        ),
      ],
    );
  }

  Widget _buildChat(VaultIndex index, ThemeData theme) {
    final scheme = theme.colorScheme;
    const examples = [
      'Tóm tắt kiến thức cần nhớ cho môn CSD201',
      'So sánh process và thread, lấy ví dụ',
      'Mình nên học lại những khái niệm nào trước khi học SWP391?',
    ];
    return Column(
      children: [
        Expanded(
          child: _chat.isEmpty
              ? Center(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final e in examples)
                        ActionChip(
                          avatar: const Icon(Icons.lightbulb_outline, size: 16),
                          label: Text(e),
                          onPressed: () {
                            _input.text = e;
                            _send(index);
                          },
                        ),
                    ],
                  ),
                )
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  children: [
                    for (final m in _chat)
                      Align(
                        alignment: m.role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 820),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: m.role == 'user' ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: m.role == 'user'
                              ? SelectableText(m.content)
                              : NotePreview(content: m.content.isEmpty ? '…' : m.content, padding: EdgeInsets.zero),
                        ),
                      ),
                  ],
                ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Row(
            children: [
              if (_chat.isNotEmpty)
                IconButton(
                  tooltip: 'Cuộc trò chuyện mới',
                  onPressed: _busy == null ? () => _setScope(_coursePath) : null,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  onSubmitted: (_) => _send(index),
                  decoration: const InputDecoration(hintText: 'Hỏi bất cứ điều gì về các ghi chú của bạn…'),
                ),
              ),
              const SizedBox(width: 8),
              if (_busy != null)
                IconButton(
                  tooltip: 'Dừng',
                  onPressed: () {
                    _sub?.cancel();
                    setState(() => _busy = null);
                  },
                  icon: const Icon(Icons.stop_circle_outlined),
                )
              else
                IconButton.filled(onPressed: () => _send(index), icon: const Icon(Icons.send)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuiz(VaultIndex index, ThemeData theme) {
    final quiz = _quiz;
    final scheme = theme.colorScheme;
    final correct = quiz == null
        ? 0
        : [for (var i = 0; i < quiz.length; i++) _answers[i] == quiz[i].answerIndex].where((x) => x).length;

    final controls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Số câu:'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 5, label: Text('5')),
              ButtonSegment(value: 10, label: Text('10')),
              ButtonSegment(value: 20, label: Text('20')),
            ],
            selected: {_quizCount},
            onSelectionChanged: (s) => setState(() => _quizCount = s.first),
          ),
          FilledButton.icon(
            onPressed: _busy == null ? () => _makeQuiz(index) : null,
            icon: const Icon(Icons.auto_awesome),
            label: Text(quiz == null ? 'Tạo đề' : 'Tạo đề mới'),
          ),
          if (quiz != null)
            OutlinedButton.icon(
              onPressed: _saveQuiz,
              icon: const Icon(Icons.save_alt),
              label: const Text('Lưu đề vào vault'),
            ),
        ],
      ),
    );

    if (quiz == null) {
      return Column(
        children: [
          controls,
          const Expanded(
            child: EmptyState(
              icon: Icons.quiz_outlined,
              title: 'Chọn phạm vi và số câu rồi bấm "Tạo đề"',
              message: 'Đề có 4 lựa chọn mỗi câu, chấm điểm và giải thích sau khi nộp. Có thể lưu thành note trong Quizzes/.',
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        controls,
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            itemCount: quiz.length + 1,
            itemBuilder: (_, i) {
              if (i == quiz.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: _submitted
                      ? Card(
                          color: scheme.primaryContainer,
                          child: ListTile(
                            leading: const Icon(Icons.emoji_events_outlined),
                            title: Text('Điểm: $correct/${quiz.length}'),
                            subtitle: Text('${(correct * 10 / quiz.length).toStringAsFixed(1)}/10 điểm'),
                            trailing: TextButton(
                              onPressed: () => setState(() {
                                _answers = List.filled(quiz.length, null);
                                _submitted = false;
                              }),
                              child: const Text('Làm lại'),
                            ),
                          ),
                        )
                      : Center(
                          child: FilledButton.icon(
                            onPressed: () => setState(() => _submitted = true),
                            icon: const Icon(Icons.check),
                            label: Text('Nộp bài (${_answers.where((a) => a != null).length}/${quiz.length} câu)'),
                          ),
                        ),
                );
              }
              return _QuestionCard(
                number: i + 1,
                question: quiz[i],
                selected: _answers[i],
                submitted: _submitted,
                onSelect: (v) => setState(() => _answers = [..._answers]..[i] = v),
                onOpenSource: (title) {
                  final path = index.resolve(title);
                  if (path != null) openNote(ref, path);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.number,
    required this.question,
    required this.selected,
    required this.submitted,
    required this.onSelect,
    required this.onOpenSource,
  });

  final int number;
  final QuizQuestion question;
  final int? selected;
  final bool submitted;
  final ValueChanged<int?> onSelect;
  final ValueChanged<String> onOpenSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final right = selected == question.answerIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Câu $number. ', style: theme.textTheme.titleSmall),
                  Expanded(
                    child: NotePreview(content: question.question, padding: EdgeInsets.zero),
                  ),
                  if (submitted)
                    Icon(
                      right ? Icons.check_circle : Icons.cancel,
                      color: right ? Colors.green : theme.colorScheme.error,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              RadioGroup<int>(
                groupValue: selected,
                onChanged: submitted ? (_) {} : onSelect,
                child: Column(
                  children: [
                    for (var j = 0; j < question.options.length; j++)
                      RadioListTile<int>(
                        value: j,
                        dense: true,
                        enabled: !submitted,
                        title: Text('${'ABCDEFGH'[j]}. ${question.options[j]}'),
                        tileColor: submitted && j == question.answerIndex
                            ? Colors.green.withValues(alpha: 0.15)
                            : submitted && j == selected
                            ? theme.colorScheme.errorContainer
                            : null,
                      ),
                  ],
                ),
              ),
              if (submitted) ...[
                const SizedBox(height: 8),
                Text(
                  'Đáp án: ${'ABCDEFGH'[question.answerIndex]}. ${question.explanation}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (question.source != null)
                  TextButton.icon(
                    onPressed: () => onOpenSource(question.source!),
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: Text('Xem lại: ${question.source}'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
