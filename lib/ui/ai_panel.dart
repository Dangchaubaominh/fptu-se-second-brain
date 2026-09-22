import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai_assistant.dart';
import '../core/claude_client.dart';
import '../core/flashcards.dart';
import '../core/vault_index.dart';
import '../state/providers.dart';
import 'note_preview.dart';
import 'widgets.dart';

class AiPanel extends ConsumerStatefulWidget {
  const AiPanel({super.key, required this.notePath, required this.onBeforeWrite});
  final String notePath;

  /// Flushes unsaved editor changes before the AI appends to the file.
  final Future<void> Function() onBeforeWrite;

  @override
  ConsumerState<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends ConsumerState<AiPanel> with AutomaticKeepAliveClientMixin {
  String? _summary;
  List<({String question, String answer})>? _cards;
  final Set<int> _picked = {};
  final List<ChatMessage> _chat = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<String>? _sub;
  String? _busy;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _run(String label, Stream<String> stream, void Function(String chunk) onChunk) {
    _sub?.cancel();
    setState(() {
      _busy = label;
      _error = null;
    });
    _sub = stream.listen(
      (chunk) {
        setState(() => onChunk(chunk));
        _scrollToEnd();
      },
      onError: (Object e) => setState(() {
        _error = '$e';
        _busy = null;
      }),
      onDone: () => setState(() => _busy = null),
      cancelOnError: true,
    );
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  void _summarize() {
    final (ai, note, index) = _ctx();
    if (ai == null || note == null) return;
    _summary = '';
    _run('Đang tóm tắt…', ai.summarize(note, index!), (c) => _summary = _summary! + c);
  }

  Future<void> _flashcards() async {
    final (ai, note, index) = _ctx();
    if (ai == null || note == null) return;
    setState(() {
      _busy = 'Đang tạo flashcard…';
      _error = null;
    });
    try {
      final cards = await ai.generateFlashcards(note, index!);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _picked
          ..clear()
          ..addAll(List.generate(cards.length, (i) => i));
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _send() {
    final text = _input.text.trim();
    final (ai, note, index) = _ctx();
    if (text.isEmpty || ai == null || note == null || _busy != null) return;
    _input.clear();
    _chat.add((role: 'user', content: text));
    final history = List<ChatMessage>.of(_chat);
    _chat.add((role: 'assistant', content: ''));
    _run('Claude đang trả lời…', ai.chat(note, index!, history), (c) {
      final last = _chat.removeLast();
      _chat.add((role: 'assistant', content: last.content + c));
    });
  }

  Future<void> _append(String text, String heading) async {
    await widget.onBeforeWrite();
    await ref.read(vaultProvider.notifier).appendToNote(widget.notePath, text, underHeading: heading);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã ghi vào mục "$heading" của note')));
    }
  }

  (AiAssistant?, Note?, VaultIndex?) _ctx() {
    final index = ref.read(vaultProvider).value;
    return (ref.read(aiProvider), index?.notes[widget.notePath], index);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ai = ref.watch(aiProvider);
    final theme = Theme.of(context);
    if (ai == null) {
      return EmptyState(
        icon: Icons.key_outlined,
        title: 'Chưa có Claude API key',
        message: 'Nhập API key trong Cài đặt (hoặc đặt biến môi trường ANTHROPIC_API_KEY) để dùng trợ lý AI.',
        action: FilledButton(
          onPressed: () => ref.read(pageProvider.notifier).set(AppPage.settings),
          child: const Text('Mở Cài đặt'),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy == null ? _summarize : null,
                  icon: const Icon(Icons.summarize_outlined),
                  label: const Text('Tóm tắt'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy == null ? _flashcards : null,
                  icon: const Icon(Icons.style_outlined),
                  label: const Text('Tạo flashcard'),
                ),
              ),
            ],
          ),
        ),
        if (_busy != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Expanded(child: Text(_busy!, style: theme.textTheme.bodySmall)),
                TextButton(
                  onPressed: () {
                    _sub?.cancel();
                    setState(() => _busy = null);
                  },
                  child: const Text('Dừng'),
                ),
              ],
            ),
          ),
        if (_error != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
          ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            children: [
              if (_summary != null)
                _ResultCard(
                  title: 'Tóm tắt',
                  actions: [
                    TextButton.icon(
                      onPressed: _busy == null && _summary!.isNotEmpty
                          ? () => _append(_summary!.trim(), 'Tóm tắt AI')
                          : null,
                      icon: const Icon(Icons.playlist_add, size: 18),
                      label: const Text('Chèn vào note'),
                    ),
                  ],
                  child: NotePreview(content: _summary!.isEmpty ? '…' : _summary!, padding: EdgeInsets.zero),
                ),
              if (_cards != null)
                _ResultCard(
                  title: 'Flashcard đề xuất (${_cards!.length})',
                  actions: [
                    TextButton.icon(
                      onPressed: _picked.isEmpty
                          ? null
                          : () {
                              final text = [
                                for (final i in _picked.toList()..sort())
                                  formatFlashcard(_cards![i].question, _cards![i].answer),
                              ].join('\n');
                              _append(text, 'Flashcards');
                              setState(() => _cards = null);
                            },
                      icon: const Icon(Icons.playlist_add, size: 18),
                      label: Text('Thêm ${_picked.length} thẻ'),
                    ),
                  ],
                  child: Column(
                    children: [
                      for (var i = 0; i < _cards!.length; i++)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _picked.contains(i),
                          onChanged: (v) => setState(() => v! ? _picked.add(i) : _picked.remove(i)),
                          title: Text(_cards![i].question),
                          subtitle: Text(_cards![i].answer),
                        ),
                    ],
                  ),
                ),
              if (_chat.isNotEmpty) ...[const SizedBox(height: 8), for (final m in _chat) _Bubble(message: m)],
              if (_summary == null && _cards == null && _chat.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'Hỏi bất cứ điều gì về note này — ví dụ: "Giải thích lại bằng ví dụ dễ hiểu", '
                    '"Cho mình 3 câu trắc nghiệm kiểu FE", "So sánh với khái niệm liên quan".',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Hỏi Claude về note này…'),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(onPressed: _busy == null ? _send : null, icon: const Icon(Icons.send)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.title, required this.child, this.actions = const []});
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                ...actions,
              ],
            ),
            Padding(padding: const EdgeInsets.only(right: 8), child: child),
          ],
        ),
      ),
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.role == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: mine
            ? SelectableText(message.content)
            : NotePreview(content: message.content.isEmpty ? '…' : message.content, padding: EdgeInsets.zero),
      ),
    );
  }
}
