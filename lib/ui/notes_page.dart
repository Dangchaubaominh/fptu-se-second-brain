import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/flashcards.dart';
import '../core/vault_index.dart';
import '../state/providers.dart';
import 'ai_panel.dart';
import 'note_preview.dart';
import 'widgets.dart';

enum _Mode { edit, split, preview }

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  final _ctrl = TextEditingController();
  String? _path;
  bool _dirty = false;
  bool _saving = false;
  Timer? _saveTimer;
  _Mode _mode = _Mode.split;
  bool _showSide = true;

  @override
  void initState() {
    super.initState();
    _load(ref.read(selectedNoteProvider));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _save();
    _ctrl.dispose();
    super.dispose();
  }

  void _load(String? path) {
    _path = path;
    _ctrl.text = path == null ? '' : ref.read(vaultProvider).value?.notes[path]?.content ?? '';
    _dirty = false;
  }

  void _onChanged(String _) {
    if (!_dirty) setState(() => _dirty = true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    final path = _path;
    if (!_dirty || path == null) return;
    _dirty = false;
    _saving = true;
    if (mounted) setState(() {});
    try {
      await ref.read(vaultProvider.notifier).save(path, _ctrl.text);
    } catch (e) {
      _dirty = true;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lưu thất bại: $e')));
    }
    _saving = false;
    if (mounted) setState(() {});
  }

  Future<void> _newNote() async {
    final title = await _askText(context, 'Ghi chú mới', 'Tên ghi chú');
    if (title == null || title.isEmpty) return;
    await _save();
    final folder = _path == null ? '' : ref.read(vaultProvider).value?.notes[_path]?.folder ?? '';
    final note = await ref.read(vaultProvider.notifier).create(folder, title);
    ref.read(selectedNoteProvider.notifier).set(note.path);
  }

  Future<void> _trash() async {
    final path = _path;
    if (path == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chuyển vào thùng rác?'),
        content: Text('"$path" sẽ được chuyển vào thư mục .trash của vault (có thể khôi phục thủ công).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Chuyển')),
        ],
      ),
    );
    if (ok != true) return;
    _saveTimer?.cancel();
    _dirty = false;
    await ref.read(vaultProvider.notifier).trash(path);
    ref.read(selectedNoteProvider.notifier).set(null);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedNoteProvider, (prev, next) {
      if (next == _path) return;
      _save();
      setState(() => _load(next));
    });
    // Pick up edits made outside the app (e.g. in Obsidian) when there are no local changes.
    ref.listen(vaultProvider, (prev, next) {
      final path = _path;
      final note = path == null ? null : next.value?.notes[path];
      if (note != null && !_dirty && note.content != _ctrl.text) {
        final sel = _ctrl.selection;
        _ctrl.text = note.content;
        if (sel.end <= note.content.length) _ctrl.selection = sel;
      }
    });

    final index = ref.watch(vaultProvider).value;
    if (index == null) return const SizedBox();
    final note = _path == null ? null : index.notes[_path];

    return Row(children: [
      SizedBox(width: 260, child: _FileTree(index: index, selected: _path, onNew: _newNote)),
      const VerticalDivider(),
      Expanded(
        child: note == null
            ? EmptyState(
                icon: Icons.description_outlined,
                title: 'Chọn một ghi chú để bắt đầu',
                message: 'Hoặc tạo ghi chú mới. Mọi thay đổi được lưu tự động vào file .md.',
                action: FilledButton.icon(onPressed: _newNote, icon: const Icon(Icons.add), label: const Text('Ghi chú mới')),
              )
            : CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save},
                child: Column(children: [
                  _EditorToolbar(
                    note: note,
                    mode: _mode,
                    status: _saving ? 'Đang lưu…' : (_dirty ? 'Chưa lưu' : 'Đã lưu'),
                    showSide: _showSide,
                    onMode: (m) => setState(() => _mode = m),
                    onToggleSide: () => setState(() => _showSide = !_showSide),
                    onTrash: _trash,
                  ),
                  const Divider(),
                  Expanded(child: _buildEditorArea()),
                ]),
              ),
      ),
      if (note != null && _showSide) ...[
        const VerticalDivider(),
        SizedBox(width: 360, child: _SidePanel(note: note, index: index, onBeforeAiWrite: _save)),
      ],
    ]);
  }

  Widget _buildEditorArea() {
    final editor = Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
      child: TextField(
        controller: _ctrl,
        onChanged: _onChanged,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontFamily: 'Consolas', fontSize: 14, height: 1.5),
        decoration: const InputDecoration.collapsed(hintText: 'Viết Markdown… dùng [[ ]] để liên kết, Câu hỏi::Trả lời để tạo flashcard'),
      ),
    );
    final preview = ValueListenableBuilder(
      valueListenable: _ctrl,
      builder: (_, v, _) => NotePreview(content: v.text),
    );
    return switch (_mode) {
      _Mode.edit => editor,
      _Mode.preview => preview,
      _Mode.split => Row(children: [
          Expanded(child: editor),
          const VerticalDivider(),
          Expanded(child: preview),
        ]),
    };
  }
}

Future<String?> _askText(BuildContext context, String title, String label) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Tạo')),
      ],
    ),
  );
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.note,
    required this.mode,
    required this.status,
    required this.showSide,
    required this.onMode,
    required this.onToggleSide,
    required this.onTrash,
  });
  final Note note;
  final _Mode mode;
  final String status;
  final bool showSide;
  final ValueChanged<_Mode> onMode;
  final VoidCallback onToggleSide;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 12, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(note.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            Text('${note.path} · $status', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        SegmentedButton<_Mode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Mode.edit, icon: Icon(Icons.edit_note), tooltip: 'Soạn thảo'),
            ButtonSegment(value: _Mode.split, icon: Icon(Icons.vertical_split), tooltip: 'Chia đôi'),
            ButtonSegment(value: _Mode.preview, icon: Icon(Icons.visibility_outlined), tooltip: 'Xem'),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onMode(s.first),
        ),
        const SizedBox(width: 8),
        IconButton(tooltip: 'Chuyển vào thùng rác', onPressed: onTrash, icon: const Icon(Icons.delete_outline)),
        IconButton(
          tooltip: showSide ? 'Ẩn bảng bên' : 'Hiện liên kết & AI',
          onPressed: onToggleSide,
          icon: Icon(showSide ? Icons.view_sidebar : Icons.view_sidebar_outlined),
        ),
      ]),
    );
  }
}

class _Dir {
  final dirs = <String, _Dir>{};
  final notes = <Note>[];
}

class _FileTree extends ConsumerStatefulWidget {
  const _FileTree({required this.index, required this.selected, required this.onNew});
  final VaultIndex index;
  final String? selected;
  final VoidCallback onNew;

  @override
  ConsumerState<_FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends ConsumerState<_FileTree> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final root = _Dir();
    final f = _filter.toLowerCase();
    for (final n in widget.index.notes.values) {
      if (f.isNotEmpty && !n.path.toLowerCase().contains(f)) continue;
      var d = root;
      if (n.folder.isNotEmpty) {
        for (final part in n.folder.split('/')) {
          d = d.dirs.putIfAbsent(part, _Dir.new);
        }
      }
      d.notes.add(n);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.filter_list, size: 18), hintText: 'Lọc file…'),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          IconButton(tooltip: 'Ghi chú mới', onPressed: widget.onNew, icon: const Icon(Icons.note_add_outlined)),
        ]),
      ),
      Expanded(child: ListView(children: _buildDir(root, 0, expandAll: f.isNotEmpty))),
    ]);
  }

  List<Widget> _buildDir(_Dir d, int depth, {required bool expandAll}) {
    final theme = Theme.of(context);
    final names = d.dirs.keys.toList()..sort();
    final notes = d.notes..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return [
      for (final name in names)
        ExpansionTile(
          key: PageStorageKey('dir:$depth/$name/$expandAll'),
          dense: true,
          initiallyExpanded: expandAll || (widget.selected?.startsWith('$name/') ?? false),
          tilePadding: EdgeInsets.only(left: 12.0 + depth * 12, right: 8),
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          leading: const Icon(Icons.folder_outlined, size: 18),
          title: Text(name, style: theme.textTheme.bodyMedium),
          children: _buildDir(d.dirs[name]!, depth + 1, expandAll: expandAll),
        ),
      for (final n in notes)
        ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -3),
          contentPadding: EdgeInsets.only(left: 20.0 + depth * 12, right: 8),
          selected: n.path == widget.selected,
          selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          leading: Icon(n.isCourse ? Icons.school_outlined : Icons.description_outlined, size: 16),
          minLeadingWidth: 16,
          title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => ref.read(selectedNoteProvider.notifier).set(n.path),
        ),
    ];
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.note, required this.index, required this.onBeforeAiWrite});
  final Note note;
  final VaultIndex index;
  final Future<void> Function() onBeforeAiWrite;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [
            Tab(icon: Icon(Icons.link, size: 18), text: 'Liên kết', height: 52),
            Tab(icon: Icon(Icons.auto_awesome, size: 18), text: 'Trợ lý AI', height: 52),
          ]),
          Expanded(
            child: TabBarView(children: [
              _LinksPanel(note: note, index: index),
              AiPanel(key: ValueKey(note.path), notePath: note.path, onBeforeWrite: onBeforeAiWrite),
            ]),
          ),
        ]),
      );
}

class _LinksPanel extends ConsumerWidget {
  const _LinksPanel({required this.note, required this.index});
  final Note note;
  final VaultIndex index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final backlinks = (index.backlinks[note.path] ?? const <String>{}).map((p) => index.notes[p]!).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    final seen = <String>{};
    final outgoing = note.links.where((l) => seen.add(l.target.toLowerCase())).toList();
    final cards = parseFlashcards(note);

    Widget header(String text, int count) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('$text ($count)', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        );

    return ListView(children: [
      header('Backlinks', backlinks.length),
      if (backlinks.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Chưa có note nào liên kết tới đây.')),
      for (final b in backlinks)
        ListTile(
          dense: true,
          leading: const Icon(Icons.subdirectory_arrow_left, size: 18),
          title: Text(b.title),
          subtitle: Text(_contextLine(b, note), maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => openNote(ref, b.path),
        ),
      header('Liên kết đi', outgoing.length),
      for (final l in outgoing)
        Builder(builder: (context) {
          final resolved = index.resolve(l.target);
          return ListTile(
            dense: true,
            leading: Icon(resolved == null ? Icons.add_link : Icons.arrow_outward, size: 18),
            title: Text(l.target,
                style: resolved == null ? TextStyle(color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic) : null),
            subtitle: resolved == null ? const Text('Chưa có note – bấm để tạo') : null,
            onTap: () => followWikilink(ref, l.target),
          );
        }),
      header('Tags', note.tags.length),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in note.tags) ActionChip(label: Text('#$t'), onPressed: () => openSearch(ref, '#$t')),
        ]),
      ),
      header('Flashcards trong note', cards.length),
      for (final c in cards)
        ListTile(dense: true, title: Text(c.question), subtitle: Text(c.answer)),
      const SizedBox(height: 16),
    ]);
  }

  static String _contextLine(Note from, Note to) {
    final names = {to.title.toLowerCase(), ...to.aliases.map((a) => a.toLowerCase())};
    for (final line in from.body.split('\n')) {
      final lower = line.toLowerCase();
      if (names.any((n) => lower.contains('[[$n'))) return line.trim();
    }
    return from.path;
  }
}
