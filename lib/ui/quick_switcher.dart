import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/wikilink_completion.dart';
import '../state/providers.dart';
import 'widgets.dart';

bool _open = false;

/// Obsidian-style quick switcher (Ctrl+O): type to find a note and open it.
/// Enter on a name that doesn't exist creates the note.
Future<void> showQuickSwitcher(BuildContext context, WidgetRef ref) async {
  if (_open || ref.read(vaultProvider).value == null) return;
  _open = true;
  try {
    final result = await showDialog<_Choice>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => const _QuickSwitcher(),
    );
    if (result == null) return;
    final path = result.path ?? (await ref.read(vaultProvider.notifier).create('', result.newTitle!)).path;
    openNote(ref, path);
  } finally {
    _open = false;
  }
}

class _Choice {
  const _Choice.open(this.path) : newTitle = null;
  const _Choice.create(this.newTitle) : path = null;
  final String? path;
  final String? newTitle;
}

class _QuickSwitcher extends ConsumerStatefulWidget {
  const _QuickSwitcher();

  @override
  ConsumerState<_QuickSwitcher> createState() => _QuickSwitcherState();
}

class _QuickSwitcherState extends ConsumerState<_QuickSwitcher> {
  final _ctrl = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _onKey);
  final _scroll = ScrollController();
  int _selected = 0;
  List<LinkSuggestion> _items = const [];

  static const _rowHeight = 56.0;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _query => _ctrl.text.trim();

  /// The "create note" row appears last when nothing matches the name exactly.
  bool get _canCreate => _query.isNotEmpty && !_items.any((s) => s.note.title.toLowerCase() == _query.toLowerCase());

  int get _rowCount => _items.length + (_canCreate ? 1 : 0);

  void _submit(int i) {
    if (i < _items.length) {
      Navigator.pop(context, _Choice.open(_items[i].note.path));
    } else if (_canCreate) {
      Navigator.pop(context, _Choice.create(_query));
    }
  }

  void _move(int d) {
    if (_rowCount == 0) return;
    setState(() => _selected = (_selected + d) % _rowCount);
    // Keep the selected row visible.
    if (_scroll.hasClients) {
      final top = _selected * _rowHeight;
      final view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + _rowHeight > _scroll.offset + view) {
        _scroll.jumpTo(top + _rowHeight - view);
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
      _submit(_selected);
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent && key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(vaultProvider).value;
    if (index == null) return const SizedBox();
    _items = suggestLinks(index, _query, limit: 30);
    if (_selected >= _rowCount) _selected = 0;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Align(
      alignment: const Alignment(0, -0.6),
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  autofocus: true,
                  onChanged: (_) => setState(() => _selected = 0),
                  style: theme.textTheme.titleMedium,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Tìm hoặc tạo note… (${index.notes.length} note)',
                    border: InputBorder.none,
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const Divider(),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _rowHeight * 8),
                child: _rowCount == 0
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: EmptyState(icon: Icons.description_outlined, title: 'Vault chưa có note nào'),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemExtent: _rowHeight,
                        itemCount: _rowCount,
                        itemBuilder: (_, i) {
                          final selected = i == _selected;
                          if (i == _items.length) {
                            return ListTile(
                              selected: selected,
                              selectedTileColor: scheme.primaryContainer,
                              leading: const Icon(Icons.note_add_outlined),
                              title: Text('Tạo note mới "$_query"'),
                              subtitle: const Text('Tạo ở thư mục gốc của vault'),
                              onTap: () => _submit(i),
                            );
                          }
                          final s = _items[i];
                          return ListTile(
                            selected: selected,
                            selectedTileColor: scheme.primaryContainer,
                            selectedColor: scheme.onPrimaryContainer,
                            leading: Icon(s.note.isCourse ? Icons.school_outlined : Icons.description_outlined),
                            title: Text(
                              s.alias == null ? s.note.title : '${s.note.title}  ·  ${s.alias}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(s.note.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: _query.isEmpty
                                ? Text(relativeTime(s.note.modified), style: theme.textTheme.bodySmall)
                                : null,
                            onTap: () => _submit(i),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: scheme.surfaceContainerHighest,
                child: Text(
                  _query.isEmpty ? 'Note sửa gần đây · ↑↓ chọn · Enter mở · Esc đóng' : '↑↓ chọn · Enter mở · Esc đóng',
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
