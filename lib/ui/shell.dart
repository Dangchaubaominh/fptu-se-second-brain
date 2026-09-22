import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'courses_page.dart';
import 'dashboard_page.dart';
import 'graph_page.dart';
import 'notes_page.dart';
import 'review_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'update_dialog.dart';
import 'welcome_page.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    if (ref.read(autoUpdateCheckProvider)) {
      // Once per launch, after the first frame so a dialog can be shown.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) checkForUpdates(context, ref, manual: false);
      });
    }
  }

  static const _destinations = [
    (AppPage.dashboard, Icons.space_dashboard_outlined, Icons.space_dashboard, 'Tổng quan'),
    (AppPage.courses, Icons.school_outlined, Icons.school, 'Môn học'),
    (AppPage.notes, Icons.description_outlined, Icons.description, 'Ghi chú'),
    (AppPage.search, Icons.search, Icons.search, 'Tìm kiếm'),
    (AppPage.graph, Icons.hub_outlined, Icons.hub, 'Graph'),
    (AppPage.review, Icons.style_outlined, Icons.style, 'Ôn tập'),
    (AppPage.settings, Icons.settings_outlined, Icons.settings, 'Cài đặt'),
  ];

  @override
  Widget build(BuildContext context) {
    final vaultPath = ref.watch(settingsProvider.select((s) => s.vaultPath));
    if (vaultPath == null) return const WelcomePage();

    final vault = ref.watch(vaultProvider);
    final page = ref.watch(pageProvider);
    final due = ref.watch(dueCardsProvider).length;
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            ref.read(pageProvider.notifier).set(AppPage.search),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
            ref.read(pageProvider.notifier).set(AppPage.graph),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: page.index,
                onDestinationSelected: (i) => ref.read(pageProvider.notifier).set(AppPage.values[i]),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Tooltip(
                    message: 'FPTU SE Second Brain',
                    child: CircleAvatar(
                      backgroundColor: scheme.primary,
                      child: Icon(Icons.psychology_alt, color: scheme.onPrimary),
                    ),
                  ),
                ),
                destinations: [
                  for (final (p, icon, selIcon, label) in _destinations)
                    NavigationRailDestination(
                      icon: p == AppPage.review && due > 0 ? Badge.count(count: due, child: Icon(icon)) : Icon(icon),
                      selectedIcon: Icon(selIcon),
                      label: Text(label),
                    ),
                ],
              ),
              const VerticalDivider(),
              Expanded(
                child: vault.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _VaultError(error: e),
                  data: (_) => IndexedStack(
                    index: page.index,
                    children: const [
                      DashboardPage(),
                      CoursesPage(),
                      NotesPage(),
                      SearchPage(),
                      GraphPage(),
                      ReviewPage(),
                      SettingsPage(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultError extends ConsumerWidget {
  const _VaultError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.folder_off_outlined, size: 48),
        const SizedBox(height: 12),
        Text('Không mở được vault', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('$error', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(onPressed: () => ref.read(vaultProvider.notifier).reload(), child: const Text('Thử lại')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => ref.read(settingsProvider.notifier).setVaultPath(null),
              child: const Text('Chọn vault khác'),
            ),
          ],
        ),
      ],
    ),
  );
}
