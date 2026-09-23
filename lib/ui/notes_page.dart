import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/flashcards.dart';
import '../core/vault_index.dart';
import '../core/vault_repository.dart';
import '../state/providers.dart';
import 'ai_panel.dart';
import 'markdown_editor.dart';
import 'note_preview.dart';
import 'quick_switcher.dart';
import 'widgets.dart';

enum _Mode { edit, split, preview }

enum _ConflictChoice { reload, overwrite, keepEditing }

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  final _ctrl = TextEditingController();
  String? _path;
  String _baseContent = '';
  bool _dirty = false;
  bool _saving = false;
  bool _hasExternalChange = false;
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
    _baseContent = path == null
        ? ''
        : ref.read(vaultProvider).value?.notes[path]?.content ?? '';
    _ctrl.text = _baseContent;
    _dirty = false;
    _hasExternalChange = false;
  }

  void _onChanged(String _) {
    if (!_dirty) setState(() => _dirty = true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<bool> _save() async {
    _saveTimer?.cancel();
    final path = _path;
    if (!_dirty || path == null) return true;
    final content = _ctrl.text;
    final expectedContent = _baseContent;
    var saved = false;
    _saving = true;
    if (mounted) setState(() {});
    try {
      await ref
          .read(vaultProvider.notifier)
          .save(path, content, expectedContent: expectedContent);
      _baseContent = content;
      _hasExternalChange = false;
      _dirty = _ctrl.text != content;
      saved = true;
    } on NoteConflictException catch (e) {
      _dirty = true;
      _hasExternalChange = true;
      if (mounted) saved = await _resolveConflict(e, content);
    } catch (e) {
      _dirty = true;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lưu thất bại: $e')));
      }
    }
    _saving = false;
    if (mounted) setState(() {});
    return saved;
  }

  Future<bool> _resolveConflict(
    NoteConflictException conflict,
    String localContent,
  ) async {
    final choice = await showDialog<_ConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghi chú đã thay đổi bên ngoài'),
        content: Text(
          '"${conflict.path}" vừa được sửa bởi Obsidian hoặc ứng dụng khác. '
          'Nạp bản trên đĩa sẽ bỏ các thay đổi chưa lưu trong cửa sổ này.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ConflictChoice.keepEditing),
            child: const Text('Để tôi xử lý'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ConflictChoice.reload),
            child: const Text('Nạp bản trên đĩa'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _ConflictChoice.overwrite),
            child: const Text('Ghi đè bằng bản này'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (choice == _ConflictChoice.reload) {
      _ctrl.text = conflict.diskContent;
      _baseContent = conflict.diskContent;
      _dirty = false;
      _hasExternalChange = false;
      return true;
    }
    if (choice == _ConflictChoice.overwrite) {
      try {
        await ref
            .read(vaultProvider.notifier)
            .save(
              conflict.path,
              localContent,
              expectedContent: conflict.diskContent,
            );
        _baseContent = localContent;
        _dirty = _ctrl.text != localContent;
        _hasExternalChange = false;
        return true;
      } on NoteConflictException catch (newer) {
        return _resolveConflict(newer, localContent);
      }
    }
    return false;
  }

  Future<void> _changeSelection(String? next) async {
    if (next == _path) return;
    final current = _path;
    if (!await _save()) {
      ref.read(selectedNoteProvider.notifier).set(current);
      return;
    }
    if (mounted) setState(() => _load(next));
  }

  Future<void> _newNote() async {
    final title = await _askText(context, 'Ghi chú mới', 'Tên ghi chú');
    if (title == null || title.isEmpty) return;
    if (!await _save()) return;
    final folder = _path == null
        ? ''
        : ref.read(vaultProvider).value?.notes[_path]?.folder ?? '';
    final note = await ref.read(vaultProvider.notifier).create(folder, title);
    ref.read(selectedNoteProvider.notifier).set(note.path);
  }

  Future<void> _rename() async {
    final path = _path;
    final note = path == null
        ? null
        : ref.read(vaultProvider).value?.notes[path];
    if (note == null) return;
    final title = await _askText(
      context,
      'Đổi tên ghi chú',
      'Tên mới',
      initial: note.title,
      action: 'Đổi tên',
    );
    if (title == null || title.isEmpty || title == note.title) return;
    // Flush pending edits to the old path before the file moves.
    if (!await _save()) return;
    try {
      final r = await ref.read(vaultProvider.notifier).rename(path!, title);
      ref.read(selectedNoteProvider.notifier).set(r.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              r.linkedNotes == 0
                  ? 'Đã đổi tên thành "$title"'
                  : 'Đã đổi tên và cập nhật liên kết trong ${r.linkedNotes} ghi chú',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không đổi tên được: $e')));
      }
    }
  }

  Future<void> _insertImage() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Chọn ảnh để chèn',
      type: FileType.image,
    );
    final source = file?.path;
    if (source == null) return;
    final notifier = ref.read(vaultProvider.notifier);
    final rel = await notifier.importAttachment(source);
    final index = ref.read(vaultProvider).value!;
    final name = p.posix.basename(rel);
    final target = index.resolveAttachment(name) == rel ? name : rel;
    final embed = '![[$target]]';
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final at = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _ctrl.value = TextEditingValue(
      text: text.replaceRange(at, end, embed),
      selection: TextSelection.collapsed(offset: at + embed.length),
    );
    _onChanged(_ctrl.text);
  }

  Future<void> _trash() async {
    final path = _path;
    if (path == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chuyển vào thùng rác?'),
        content: Text(
          '"$path" sẽ được chuyển vào thư mục .trash của vault (có thể khôi phục thủ công).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Chuyển'),
          ),
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
      unawaited(_changeSelection(next));
    });
    // Pick up edits made outside the app, or mark a conflict while local edits exist.
    ref.listen(vaultProvider, (prev, next) {
      final path = _path;
      final note = path == null ? null : next.value?.notes[path];
      if (note != null && !_dirty && note.content != _ctrl.text) {
        final sel = _ctrl.selection;
        _ctrl.text = note.content;
        _baseContent = note.content;
        _hasExternalChange = false;
        if (sel.end <= note.content.length) _ctrl.selection = sel;
      } else if (note != null &&
          _dirty &&
          note.content != _baseContent &&
          !_hasExternalChange) {
        setState(() => _hasExternalChange = true);
      }
    });

    final index = ref.watch(vaultProvider).value;
    if (index == null) return const SizedBox();
    final note = _path == null ? null : index.notes[_path];
    // Narrow windows: slimmer file tree and side panel so the editor keeps enough room.
    final compact = MediaQuery.sizeOf(context).width < 1300;

    return Row(
      children: [
        SizedBox(
          width: compact ? 220 : 260,
          child: _FileTree(
            index: index,
            selected: _path,
            onNew: _newNote,
            onShowTrash: () => _showTrash(context, ref),
          ),
        ),
        const VerticalDivider(),
        Expanded(
          child: note == null
              ? EmptyState(
                  icon: Icons.description_outlined,
                  title: 'Chọn một ghi chú để bắt đầu',
                  message: 'Hoặc tạo ghi chú mới. Mọi thay đổi được lưu tự động vào file .md.',
                  action: FilledButton.icon(
                    onPressed: _newNote,
                    icon: const Icon(Icons.add),
                    label: const Text('Ghi chú mới'),
                  ),
                )
              : CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.keyS,
                      control: true,
                    ): _save,
                  },
                  child: Column(
                    children: [
                      _EditorToolbar(
                        note: note,
                        mode: _mode,
                        status: _saving
                            ? 'Đang lưu…'
                            : (_hasExternalChange
                                  ? 'Xung đột với thay đổi bên ngoài'
                                  : (_dirty ? 'Chưa lưu' : 'Đã lưu')),
                        showSide: _showSide,
                        onMode: (m) => setState(() => _mode = m),
                        onToggleSide: () =>
                            setState(() => _showSide = !_showSide),
                        onTrash: _trash,
                        onRename: _rename,
                        onInsertImage: _insertImage,
                      ),
                      const Divider(),
                      Expanded(child: _buildEditorArea(index)),
                    ],
                  ),
                ),
        ),
        if (note != null && _showSide) ...[
          const VerticalDivider(),
          SizedBox(
            width: compact ? 300 : 360,
            child: _SidePanel(
              note: note,
              index: index,
              onBeforeAiWrite: () async {
                await _save();
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEditorArea(VaultIndex index) {
    final editor = MarkdownEditor(
      controller: _ctrl,
      onChanged: _onChanged,
      index: index,
      currentPath: _path,
    );
    final preview = ValueListenableBuilder(
      valueListenable: _ctrl,
      builder: (_, v, _) => NotePreview(content: v.text, notePath: _path),
    );
    return switch (_mode) {
      _Mode.edit => editor,
      _Mode.preview => preview,
      _Mode.split => Row(
        children: [
          Expanded(child: editor),
          const VerticalDivider(),
          Expanded(child: preview),
        ],
      ),
    };
  }
}

Future<String?> _askText(
  BuildContext context,
  String title,
  String label, {
  String initial = '',
  String action = 'Tạo',
}) {
  final c = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
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
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: Text(action),
        ),
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
    required this.onRename,
    required this.onInsertImage,
  });
  final Note note;
  final _Mode mode;
  final String status;
  final bool showSide;
  final ValueChanged<_Mode> onMode;
  final VoidCallback onToggleSide;
  final VoidCallback onTrash;
  final VoidCallback onRename;
  final VoidCallback onInsertImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${note.path} · $status',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SegmentedButton<_Mode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _Mode.edit,
                icon: Icon(Icons.edit_note),
                tooltip: 'Soạn thảo',
              ),
              ButtonSegment(
                value: _Mode.split,
                icon: Icon(Icons.vertical_split),
                tooltip: 'Chia đôi',
              ),
              ButtonSegment(
                value: _Mode.preview,
                icon: Icon(Icons.visibility_outlined),
                tooltip: 'Xem',
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => onMode(s.first),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Chèn ảnh',
            onPressed: onInsertImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'Thêm',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: onRename,
                child: const ListTile(
                  leading: Icon(Icons.drive_file_rename_outline),
                  title: Text('Đổi tên'),
                ),
              ),
              PopupMenuItem(
                value: onTrash,
                child: const ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Chuyển vào thùng rác'),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: showSide ? 'Ẩn bảng bên' : 'Hiện liên kết & AI',
            onPressed: onToggleSide,
            icon: Icon(
              showSide ? Icons.view_sidebar : Icons.view_sidebar_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dir {
  final dirs = <String, _Dir>{};
  final notes = <Note>[];
}

class _FileTree extends ConsumerStatefulWidget {
  const _FileTree({
    required this.index,
    required this.selected,
    required this.onNew,
    required this.onShowTrash,
  });
  final VaultIndex index;
  final String? selected;
  final VoidCallback onNew;
  final VoidCallback onShowTrash;

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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.filter_list, size: 18),
                    hintText: 'Lọc file…',
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              IconButton(
                tooltip: 'Mở nhanh (Ctrl+O)',
                onPressed: () => showQuickSwitcher(context, ref),
                icon: const Icon(Icons.manage_search),
              ),
              IconButton(
                tooltip: 'Thùng rác',
                onPressed: widget.onShowTrash,
                icon: const Icon(Icons.restore_from_trash),
              ),
              IconButton(
                tooltip: 'Ghi chú mới',
                onPressed: widget.onNew,
                icon: const Icon(Icons.note_add_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: _buildDir(root, 0, expandAll: f.isNotEmpty),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDir(_Dir d, int depth, {required bool expandAll}) {
    final theme = Theme.of(context);
    final names = d.dirs.keys.toList()..sort();
    final notes = d.notes
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return [
      for (final name in names)
        ExpansionTile(
          key: PageStorageKey('dir:$depth/$name/$expandAll'),
          dense: true,
          initiallyExpanded:
              expandAll || (widget.selected?.startsWith('$name/') ?? false),
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
          selectedTileColor: theme.colorScheme.primaryContainer.withValues(
            alpha: 0.5,
          ),
          leading: Icon(
            n.isCourse ? Icons.school_outlined : Icons.description_outlined,
            size: 16,
          ),
          minLeadingWidth: 16,
          title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => ref.read(selectedNoteProvider.notifier).set(n.path),
        ),
    ];
  }
}

Future<void> _showTrash(
  BuildContext context,
  WidgetRef ref,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => Consumer(
    builder: (context, dialogRef, _) {
      final trash = dialogRef.watch(trashProvider);
      return AlertDialog(
        title: const Text('Thùng rác'),
        content: SizedBox(
          width: 620,
          height: 420,
          child: trash.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('Không đọc được thùng rác: $error')),
            data: (entries) => entries.isEmpty
                ? const EmptyState(
                    icon: Icons.delete_outline,
                    title: 'Thùng rác đang trống',
                    message: 'Ghi chú bị xóa sẽ xuất hiện ở đây và có thể khôi phục.',
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(
                          p.posix.basenameWithoutExtension(entry.originalPath),
                        ),
                        subtitle: Text(
                          '${entry.originalPath} · ${relativeTime(entry.deletedAt)}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Khôi phục',
                          icon: const Icon(Icons.restore),
                          onPressed: () async {
                            try {
                              final note = await dialogRef
                                  .read(vaultProvider.notifier)
                                  .restoreTrash(entry);
                              dialogRef
                                  .read(selectedNoteProvider.notifier)
                                  .set(note.path);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Đã khôi phục ${note.path}'),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Không khôi phục được: $error',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
        ],
      );
    },
  ),
);

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.note,
    required this.index,
    required this.onBeforeAiWrite,
  });
  final Note note;
  final VaultIndex index;
  final Future<void> Function() onBeforeAiWrite;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.link, size: 18), text: 'Liên kết', height: 52),
            Tab(
              icon: Icon(Icons.auto_awesome, size: 18),
              text: 'Trợ lý AI',
              height: 52,
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _LinksPanel(note: note, index: index),
              AiPanel(
                key: ValueKey(note.path),
                notePath: note.path,
                onBeforeWrite: onBeforeAiWrite,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LinksPanel extends ConsumerWidget {
  const _LinksPanel({required this.note, required this.index});
  final Note note;
  final VaultIndex index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final backlinks =
        (index.backlinks[note.path] ?? const <String>{})
            .map((p) => index.notes[p]!)
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    final seen = <String>{};
    final outgoing = note.links
        .where((l) => seen.add(l.target.toLowerCase()))
        .toList();
    final cards = parseFlashcards(note);

    Widget header(String text, int count) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        '$text ($count)',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return ListView(
      children: [
        header('Backlinks', backlinks.length),
        if (backlinks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Chưa có note nào liên kết tới đây.'),
          ),
        for (final b in backlinks)
          ListTile(
            dense: true,
            leading: const Icon(Icons.subdirectory_arrow_left, size: 18),
            title: Text(b.title),
            subtitle: Text(
              _contextLine(b, note),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => openNote(ref, b.path),
          ),
        header('Liên kết đi', outgoing.length),
        for (final l in outgoing)
          Builder(
            builder: (context) {
              final resolved = index.resolve(l.target);
              return ListTile(
                dense: true,
                leading: Icon(
                  resolved == null ? Icons.add_link : Icons.arrow_outward,
                  size: 18,
                ),
                title: Text(
                  l.target,
                  style: resolved == null
                      ? TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        )
                      : null,
                ),
                subtitle: resolved == null
                    ? const Text('Chưa có note – bấm để tạo')
                    : null,
                onTap: () => followWikilink(ref, l.target),
              );
            },
          ),
        header('Tags', note.tags.length),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in note.tags)
                ActionChip(
                  label: Text('#$t'),
                  onPressed: () => openSearch(ref, '#$t'),
                ),
            ],
          ),
        ),
        header('Flashcards trong note', cards.length),
        for (final c in cards)
          ListTile(
            dense: true,
            title: Text(c.question),
            subtitle: Text(c.answer),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  static String _contextLine(Note from, Note to) {
    final names = {
      to.title.toLowerCase(),
      ...to.aliases.map((a) => a.toLowerCase()),
    };
    for (final line in from.body.split('\n')) {
      final lower = line.toLowerCase();
      if (names.any((n) => lower.contains('[[$n'))) return line.trim();
    }
    return from.path;
  }
}
