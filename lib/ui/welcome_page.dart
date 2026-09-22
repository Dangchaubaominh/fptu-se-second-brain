import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/sample_vault.dart';
import '../state/providers.dart';

/// Opens an existing Obsidian vault or creates the FPTU SE starter vault.
Future<void> pickVault(WidgetRef ref) async {
  final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Chọn thư mục Obsidian vault');
  if (dir != null) await ref.read(settingsProvider.notifier).setVaultPath(dir);
}

Future<void> createSampleVault(BuildContext context, WidgetRef ref) async {
  final parent = await FilePicker.getDirectoryPath(dialogTitle: 'Chọn nơi tạo vault mẫu');
  if (parent == null) return;
  final dir = p.join(parent, 'FPTU-SE-Brain');
  try {
    await SampleVault.create(dir);
    await ref.read(settingsProvider.notifier).setVaultPath(dir);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tạo được vault: $e')));
    }
  }
}

class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer.withValues(alpha: 0.5), scheme.surface],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: scheme.primary,
                    child: Icon(Icons.psychology_alt, size: 36, color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'FPTU SE Second Brain',
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quản lý kiến thức ngành Kỹ thuật phần mềm theo từng kỳ, liên kết khái niệm như Obsidian, '
                    'ôn tập bằng flashcard và hỏi AI ngay trên ghi chú của bạn.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  _ActionCard(
                    icon: Icons.folder_open,
                    title: 'Mở Obsidian vault có sẵn',
                    subtitle: 'Chọn thư mục vault. App đọc/ghi trực tiếp file .md, dùng song song với Obsidian.',
                    onTap: () => pickVault(ref),
                  ),
                  const SizedBox(height: 12),
                  _ActionCard(
                    icon: Icons.auto_awesome,
                    title: 'Tạo vault mẫu FPTU SE',
                    subtitle: 'Lộ trình 9 kỳ, ~40 môn, các note khái niệm kèm flashcard để bắt đầu ngay.',
                    onTap: () => createSampleVault(context, ref),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: scheme.primary, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
