import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/vault_index.dart';
import '../core/wikilink_completion.dart';

/// Plain-text Markdown editor with Obsidian-style `[[` link suggestions.
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.index,
    this.currentPath,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VaultIndex index;
  final String? currentPath;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  static const _style = TextStyle(fontFamily: 'Consolas', fontSize: 14, height: 1.5);
  static const _padding = EdgeInsets.fromLTRB(24, 16, 16, 16);
  static const _popupWidth = 340.0;
  static const _rowHeight = 48.0;

  late final _focus = FocusNode(onKeyEvent: _onKey);
  final _scroll = ScrollController();
  WikilinkQuery? _query;
  List<LinkSuggestion> _items = const [];
  int _selected = 0;

  /// Query the user dismissed with Esc; stays hidden until the query changes.
  WikilinkQuery? _dismissed;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _focus.addListener(_refresh);
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(MarkdownEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
    if (old.index != widget.index) _refresh();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_query != null) setState(() {});
  }

  void _refresh() {
    final v = widget.controller.value;
    final q = v.selection.isCollapsed && _focus.hasFocus ? activeWikilinkQuery(v.text, v.selection.baseOffset) : null;
    final dismissed = q != null && _dismissed != null && q.start == _dismissed!.start && q.query == _dismissed!.query;
    final show = q != null && !dismissed;
    final items = show ? suggestLinks(widget.index, q.query, exclude: widget.currentPath) : const <LinkSuggestion>[];
    if (!show && _query == null) return;
    setState(() {
      if (show && (_query?.query != q.query || _query?.start != q.start)) _selected = 0;
      _query = show ? q : null;
      _items = items;
      _selected = items.isEmpty ? 0 : min(_selected, items.length - 1);
    });
  }

  void _accept(int i) {
    final q = _query;
    if (q == null) return;
    final ctrl = widget.controller;
    // No match: link to a new note named after what was typed (created on click, like Obsidian).
    final target = _items.isEmpty ? q.query.trim() : linkTarget(widget.index, _items[i]);
    if (target.isEmpty) return;
    final r = applyWikilinkCompletion(ctrl.text, ctrl.selection.baseOffset, q, target);
    ctrl.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.cursor),
    );
    widget.onChanged(r.text);
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_query == null || e is KeyUpEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      if (_items.isEmpty) return KeyEventResult.ignored;
      final d = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() => _selected = (_selected + d) % _items.length);
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
      if (_items.isEmpty && _query!.query.trim().isEmpty) return KeyEventResult.ignored;
      _accept(_selected);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _dismissed = _query;
        _query = null;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Caret position inside the scrolled text, relative to the text's top-left.
  Offset _caretOffset(double width) {
    final tp = TextPainter(
      text: TextSpan(text: widget.controller.text, style: _style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: max(0, width));
    final caret = tp.getOffsetForCaret(TextPosition(offset: widget.controller.selection.baseOffset), Rect.zero);
    tp.dispose();
    return caret - Offset(0, _scroll.hasClients ? _scroll.offset : 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final field = Padding(
          padding: _padding,
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            scrollController: _scroll,
            onChanged: widget.onChanged,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: _style,
            decoration: const InputDecoration.collapsed(
              hintText: 'Viết Markdown… gõ [[ để liên kết note, Câu hỏi::Trả lời để tạo flashcard',
            ),
          ),
        );
        if (_query == null) return Stack(children: [Positioned.fill(child: field)]);

        final lineHeight = _style.fontSize! * _style.height! * MediaQuery.textScalerOf(context).scale(1);
        final caret = _caretOffset(c.maxWidth - _padding.horizontal);
        final popupHeight = _rowHeight * max(1, _items.length) + 32;
        var left = _padding.left + caret.dx;
        left = left.clamp(8.0, max(8.0, c.maxWidth - _popupWidth - 8));
        var top = _padding.top + caret.dy + lineHeight + 4;
        if (top + popupHeight > c.maxHeight) top = _padding.top + caret.dy - popupHeight - 4; // flip above
        top = top.clamp(0.0, max(0.0, c.maxHeight - popupHeight));

        return Stack(
          children: [
            Positioned.fill(child: field),
            Positioned(
              left: left,
              top: top,
              width: min(_popupWidth, c.maxWidth - 16),
              // Counts as part of the text field, so clicking a suggestion doesn't unfocus the editor.
              child: TextFieldTapRegion(
                child: _SuggestionList(
                  items: _items,
                  selected: _selected,
                  query: _query!.query,
                  onTap: _accept,
                  onHover: (i) => setState(() => _selected = i),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.items,
    required this.selected,
    required this.query,
    required this.onTap,
    required this.onHover,
  });

  final List<LinkSuggestion> items;
  final int selected;
  final String query;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_link, size: 18),
              title: Text(query.trim().isEmpty ? 'Gõ tên note…' : 'Liên kết tới note mới "${query.trim()}"'),
              subtitle: query.trim().isEmpty ? null : const Text('Enter để chèn · note được tạo khi bấm vào link'),
              onTap: query.trim().isEmpty ? null : () => onTap(0),
            ),
          for (var i = 0; i < items.length; i++)
            MouseRegion(
              onEnter: (_) => onHover(i),
              child: ListTile(
                dense: true,
                selected: i == selected,
                selectedTileColor: scheme.primaryContainer,
                selectedColor: scheme.onPrimaryContainer,
                leading: Icon(items[i].note.isCourse ? Icons.school_outlined : Icons.description_outlined, size: 18),
                title: Text(
                  items[i].alias == null ? items[i].note.title : '${items[i].alias}  →  ${items[i].note.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(items[i].note.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => onTap(i),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: scheme.surfaceContainerHighest,
            child: Text(
              '↑↓ chọn · Enter/Tab chèn · Esc đóng',
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
