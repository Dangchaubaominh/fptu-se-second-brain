import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/flashcards.dart';
import '../core/vault_index.dart';
import '../state/providers.dart';
import 'note_preview.dart';
import 'widgets.dart';

/// Spaced-repetition review. Cards are `Q::A` lines from the vault's notes,
/// grouped into decks by course (the course note plus the notes it links to).
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  String? _deck; // course note path, null = all
  List<Flashcard>? _queue;
  bool _revealed = false;
  int _reviewed = 0;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Set<String>? _deckPaths(VaultIndex index) => _deck == null ? null : {_deck!, ...?index.outgoing[_deck]};

  List<Flashcard> _dueIn(VaultIndex index) {
    final paths = _deckPaths(index);
    return ref.read(dueCardsProvider).where((c) => paths == null || paths.contains(c.notePath)).toList()..shuffle();
  }

  void _start(VaultIndex index) {
    setState(() {
      _queue = _dueIn(index);
      _revealed = false;
      _reviewed = 0;
    });
    _focus.requestFocus();
  }

  Future<void> _grade(Grade g) async {
    final q = _queue;
    if (q == null || q.isEmpty || !_revealed) return;
    final card = q.removeAt(0);
    if (g == Grade.again) q.add(card); // see it again this session
    setState(() {
      _revealed = false;
      _reviewed++;
    });
    await ref.read(srsProvider.notifier).grade(card, g);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(vaultProvider).value;
    if (index == null) return const SizedBox();
    final all = ref.watch(flashcardsProvider);
    final due = ref.watch(dueCardsProvider);
    final states = ref.watch(srsProvider).value ?? const {};
    final theme = Theme.of(context);

    final decks = index.courses
        .map((c) {
          final paths = {c.path, ...?index.outgoing[c.path]};
          return (
            c,
            all.where((x) => paths.contains(x.notePath)).length,
            due.where((x) => paths.contains(x.notePath)).length,
          );
        })
        .where((d) => d.$2 > 0)
        .toList();

    final queue = _queue;
    if (queue != null && queue.isNotEmpty) return _buildSession(queue, theme);

    final paths = _deckPaths(index);
    final dueHere = due.where((c) => paths == null || paths.contains(c.notePath)).length;
    DateTime? nextDue;
    for (final c in all) {
      final d = states[c.id]?.due;
      if (d != null && d.isAfter(DateTime.now()) && (nextDue == null || d.isBefore(nextDue))) nextDue = d;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        PageHeader(
          title: 'Ôn tập flashcard',
          subtitle: 'Viết "Câu hỏi::Trả lời" trong bất kỳ note nào. Lịch ôn theo thuật toán SM-2, lưu ở .fptu/srs.json trong vault.',
        ),
        if (queue != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Text('🎉', style: TextStyle(fontSize: 28)),
                title: Text('Hoàn thành phiên ôn tập: $_reviewed lượt'),
                subtitle: nextDue == null
                    ? null
                    : Text(
                        'Thẻ tiếp theo đến hạn: ${nextDue.day}/${nextDue.month} ${nextDue.hour}:${nextDue.minute.toString().padLeft(2, '0')}',
                      ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Text('Chọn bộ thẻ', style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('Tất cả · ${due.length}/${all.length}'),
                selected: _deck == null,
                onSelected: (_) => setState(() => _deck = null),
              ),
              for (final (c, total, d) in decks)
                ChoiceChip(
                  label: Text('${c.courseCode} · $d/$total'),
                  selected: _deck == c.path,
                  onSelected: (_) => setState(() => _deck = c.path),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: all.isEmpty
              ? const EmptyState(
                  icon: Icons.style_outlined,
                  title: 'Chưa có flashcard nào',
                  message: 'Thêm dòng "Câu hỏi::Trả lời" vào note, hoặc dùng Trợ lý AI → "Tạo flashcard".',
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20)),
                  onPressed: dueHere == 0 ? null : () => _start(index),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(dueHere == 0 ? 'Không có thẻ đến hạn' : 'Bắt đầu ôn $dueHere thẻ'),
                ),
        ),
      ],
    );
  }

  Widget _buildSession(List<Flashcard> queue, ThemeData theme) {
    final card = queue.first;
    final index = ref.watch(vaultProvider).value!;
    final source = index.notes[card.notePath];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () => setState(() => _revealed = true),
        const SingleActivator(LogicalKeyboardKey.digit1): () => _grade(Grade.again),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _grade(Grade.hard),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _grade(Grade.good),
        const SingleActivator(LogicalKeyboardKey.digit4): () => _grade(Grade.easy),
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(() => _queue = null),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Column(
          children: [
            PageHeader(
              title: 'Đang ôn tập',
              subtitle: 'Còn ${queue.length} thẻ · đã ôn $_reviewed · Space: lật thẻ · 1–4: chấm điểm · Esc: dừng',
              actions: [TextButton(onPressed: () => setState(() => _queue = null), child: const Text('Kết thúc'))],
            ),
            LinearProgressIndicator(value: _reviewed / (_reviewed + queue.length)),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ActionChip(
                              avatar: const Icon(Icons.description_outlined, size: 16),
                              label: Text(source?.title ?? card.notePath),
                              onPressed: () => openNote(ref, card.notePath),
                            ),
                            const SizedBox(height: 16),
                            NotePreview(content: card.question, padding: EdgeInsets.zero),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 16),
                            AnimatedCrossFade(
                              duration: const Duration(milliseconds: 200),
                              crossFadeState: _revealed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                              firstChild: FilledButton.tonal(
                                onPressed: () => setState(() => _revealed = true),
                                child: const Padding(padding: EdgeInsets.all(12), child: Text('Hiện đáp án (Space)')),
                              ),
                              secondChild: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  NotePreview(content: card.answer, padding: EdgeInsets.zero),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      for (final (g, label, color) in [
                                        (Grade.again, '1 · Quên', Colors.red),
                                        (Grade.hard, '2 · Khó', Colors.orange),
                                        (Grade.good, '3 · Nhớ', Colors.green),
                                        (Grade.easy, '4 · Dễ', Colors.blue),
                                      ])
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: color,
                                                side: BorderSide(color: color.withValues(alpha: 0.6)),
                                                padding: const EdgeInsets.symmetric(vertical: 14),
                                              ),
                                              onPressed: () => _grade(g),
                                              child: Text(label),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
