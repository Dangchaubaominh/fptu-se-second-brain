import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/vault_index.dart';
import '../state/providers.dart';
import 'widgets.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(vaultProvider).value;
    if (index == null) return const SizedBox();
    final theme = Theme.of(context);
    final courses = index.courses;
    final done = courses.where((c) => c.status == CourseStatus.done).length;
    final learning = courses.where((c) => c.status == CourseStatus.learning).toList();
    final cards = ref.watch(flashcardsProvider);
    final due = ref.watch(dueCardsProvider);
    final semesters = <int, List<Note>>{};
    for (final c in courses) {
      (semesters[c.semester] ??= []).add(c);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        PageHeader(
          title: 'Xin chào 👋',
          subtitle: 'Vault: ${index.name} · ${index.root}',
          actions: [
            IconButton(
              tooltip: 'Tải lại vault',
              onPressed: () => ref.read(vaultProvider.notifier).reload(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(icon: Icons.description, label: 'Ghi chú', value: '${index.notes.length}'),
              _StatCard(icon: Icons.link, label: 'Liên kết', value: '${index.linkCount}'),
              _StatCard(
                icon: Icons.school,
                label: 'Môn đã hoàn thành',
                value: '$done/${courses.length}',
                onTap: () => ref.read(pageProvider.notifier).set(AppPage.courses),
              ),
              _StatCard(
                icon: Icons.style,
                label: 'Thẻ cần ôn hôm nay',
                value: '${due.length}/${cards.length}',
                highlight: due.isNotEmpty,
                onTap: () => ref.read(pageProvider.notifier).set(AppPage.review),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 900;
          final left = _Section(
            title: 'Tiến độ theo kỳ',
            child: semesters.isEmpty
                ? const Text('Chưa có note môn học nào (frontmatter `type: course`).')
                : Column(
                    children: [
                      for (final e in (semesters.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                        _SemesterProgress(semester: e.key, courses: e.value),
                    ],
                  ),
          );
          final right = Column(children: [
            _Section(
              title: 'Đang học',
              child: learning.isEmpty
                  ? Text('Chưa đánh dấu môn nào là "Đang học". Vào mục Môn học để cập nhật.',
                      style: theme.textTheme.bodySmall)
                  : Column(children: [
                      for (final c in learning)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.timelapse, color: statusColor(c.status, theme.colorScheme)),
                          title: Text(c.courseCode),
                          subtitle: Text(c.courseName),
                          onTap: () => openNote(ref, c.path),
                        ),
                    ]),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Chỉnh sửa gần đây',
              child: Column(children: [
                for (final n in index.recent.take(8))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(relativeTime(n.modified), style: theme.textTheme.bodySmall),
                    onTap: () => openNote(ref, n.path),
                  ),
              ]),
            ),
          ]);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: left),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: right),
                  ])
                : Column(children: [left, const SizedBox(height: 16), right]),
          );
        }),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, this.onTap, this.highlight = false});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 220,
      child: Card(
        color: highlight ? scheme.primaryContainer : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(icon, color: scheme.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

class _SemesterProgress extends StatelessWidget {
  const _SemesterProgress({required this.semester, required this.courses});
  final int semester;
  final List<Note> courses;

  @override
  Widget build(BuildContext context) {
    final done = courses.where((c) => c.status == CourseStatus.done).length;
    final learning = courses.where((c) => c.status == CourseStatus.learning).length;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 56, child: Text('Kỳ $semester', style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(children: [
                if (done > 0) Expanded(flex: done, child: Container(color: statusColor(CourseStatus.done, scheme))),
                if (learning > 0)
                  Expanded(flex: learning, child: Container(color: statusColor(CourseStatus.learning, scheme))),
                if (courses.length - done - learning > 0)
                  Expanded(
                    flex: courses.length - done - learning,
                    child: Container(color: scheme.surfaceContainerHighest),
                  ),
              ]),
            ),
          ),
        ),
        SizedBox(width: 56, child: Text('$done/${courses.length}', textAlign: TextAlign.end)),
      ]),
    );
  }
}
