import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/flashcards.dart';
import '../core/markdown_utils.dart';
import '../core/vault_index.dart';
import '../state/providers.dart';
import 'widgets.dart';

class CoursesPage extends ConsumerStatefulWidget {
  const CoursesPage({super.key});

  @override
  ConsumerState<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends ConsumerState<CoursesPage> {
  CourseStatus? _filter;

  Future<void> _newCourse(VaultIndex index) async {
    final code = TextEditingController();
    final name = TextEditingController();
    final sem = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm môn học'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, autofocus: true, decoration: const InputDecoration(labelText: 'Mã môn (vd: PRM392)')),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Tên môn')),
            const SizedBox(height: 12),
            TextField(controller: sem, decoration: const InputDecoration(labelText: 'Kỳ'), keyboardType: TextInputType.number),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tạo')),
        ],
      ),
    );
    if (ok != true || code.text.trim().isEmpty) return;
    final c = code.text.trim().toUpperCase();
    final s = int.tryParse(sem.text) ?? 1;
    final note = await ref.read(vaultProvider.notifier).create('Courses', c, content: '''
---
type: course
code: $c
name: ${name.text.trim()}
semester: $s
status: todo
prerequisites: []
tags: [course, ky$s]
---
# $c — ${name.text.trim()}

## Khái niệm chính
-

## Ghi chú buổi học
-

## Flashcards
''');
    if (mounted) openNote(ref, note.path);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(vaultProvider).value;
    if (index == null) return const SizedBox();
    final all = index.courses;
    final courses = _filter == null ? all : all.where((c) => c.status == _filter).toList();
    final bySem = <int, List<Note>>{};
    for (final c in courses) {
      (bySem[c.semester] ??= []).add(c);
    }
    final sems = bySem.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Lộ trình môn học',
          subtitle: 'Mỗi môn là một note có frontmatter `type: course`. Đổi trạng thái sẽ ghi thẳng vào file.',
          actions: [
            FilledButton.icon(
              onPressed: () => _newCourse(index),
              icon: const Icon(Icons.add),
              label: const Text('Thêm môn'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(spacing: 8, children: [
            ChoiceChip(label: Text('Tất cả (${all.length})'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
            for (final s in CourseStatus.values)
              ChoiceChip(
                avatar: Icon(statusIcon(s), size: 16),
                label: Text('${s.label} (${all.where((c) => c.status == s).length})'),
                selected: _filter == s,
                onSelected: (_) => setState(() => _filter = s),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: all.isEmpty
              ? const EmptyState(
                  icon: Icons.school_outlined,
                  title: 'Chưa có môn học',
                  message: 'Thêm môn mới, hoặc thêm `type: course` vào frontmatter của một note có sẵn.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    for (final s in sems) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        child: Text(s == 0 ? 'Chưa xếp kỳ' : 'Kỳ $s',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [for (final c in bySem[s]!) _CourseCard(course: c, index: index)],
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _CourseCard extends ConsumerWidget {
  const _CourseCard({required this.course, required this.index});
  final Note course;
  final VaultIndex index;

  Future<void> _setStatus(WidgetRef ref, CourseStatus s) =>
      ref.read(vaultProvider.notifier).save(course.path, setFrontmatterField(course.content, 'status', s.name));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final linked = index.outgoing[course.path] ?? const <String>{};
    final cardCount = [course.path, ...linked]
        .map((p) => index.notes[p])
        .whereType<Note>()
        .fold<int>(0, (s, n) => s + parseFlashcards(n).length);
    final missingPrereq = course.prerequisites.where((code) {
      final p = index.resolve(code);
      return p != null && index.notes[p]!.status != CourseStatus.done;
    }).toList();

    return SizedBox(
      width: 280,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openNote(ref, course.path),
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: statusColor(course.status, scheme), width: 4))),
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(course.courseCode,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                PopupMenuButton<CourseStatus>(
                  tooltip: 'Đổi trạng thái',
                  onSelected: (s) => _setStatus(ref, s),
                  itemBuilder: (_) => [
                    for (final s in CourseStatus.values)
                      PopupMenuItem(
                        value: s,
                        child: Row(children: [
                          Icon(statusIcon(s), color: statusColor(s, scheme), size: 18),
                          const SizedBox(width: 8),
                          Text(s.label),
                        ]),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(statusIcon(course.status), color: statusColor(course.status, scheme), size: 18),
                      const SizedBox(width: 4),
                      Text(course.status.label, style: theme.textTheme.labelMedium),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ]),
                  ),
                ),
              ]),
              Text(course.courseName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Wrap(spacing: 12, runSpacing: 4, children: [
                _Meta(icon: Icons.link, text: '${linked.length} liên kết'),
                _Meta(icon: Icons.style_outlined, text: '$cardCount thẻ'),
                if (course.prerequisites.isNotEmpty)
                  Tooltip(
                    message: missingPrereq.isEmpty
                        ? 'Đã hoàn thành môn tiên quyết'
                        : 'Chưa hoàn thành: ${missingPrereq.join(', ')}',
                    child: _Meta(
                      icon: missingPrereq.isEmpty ? Icons.lock_open : Icons.lock_outline,
                      text: course.prerequisites.join(', '),
                      color: missingPrereq.isEmpty ? null : scheme.error,
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: c),
      const SizedBox(width: 4),
      Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c)),
    ]);
  }
}
