import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update_checker.dart';
import '../state/providers.dart';
import 'note_preview.dart';

/// Checks GitHub for a newer release and offers to download it.
/// Automatic checks stay silent on errors and respect "skip this version";
/// manual checks (from Settings) always report the result.
Future<void> checkForUpdates(BuildContext context, WidgetRef ref, {required bool manual}) async {
  final String current;
  try {
    current = await ref.read(appVersionProvider.future);
  } catch (_) {
    return;
  }
  final release = await fetchLatestRelease();
  if (!context.mounted) return;

  void snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  if (release == null) {
    if (manual) snack('Không kiểm tra được cập nhật (mất mạng, hoặc repo GitHub đang để Private).');
    return;
  }
  if (!isNewerVersion(release.version, current)) {
    if (manual) snack('Bạn đang dùng bản mới nhất ($current).');
    return;
  }
  final prefs = ref.read(prefsProvider);
  if (!manual && prefs.getString('skippedUpdate') == release.version) return;

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update_alt),
      title: Text('Có bản ${release.version}, tải về?'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn đang dùng bản $current. Tải file zip, đóng app rồi giải nén đè lên thư mục cũ. '
              'Ghi chú và lịch ôn tập nằm trong vault nên không bị ảnh hưởng.',
            ),
            if (release.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Có gì mới', style: Theme.of(ctx).textTheme.titleSmall),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: NotePreview(content: release.notes, padding: const EdgeInsets.symmetric(vertical: 8)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: const Text('Bỏ qua bản này')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Để sau')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, 'download'),
          icon: const Icon(Icons.download),
          label: const Text('Tải về'),
        ),
      ],
    ),
  );
  if (choice == 'skip') await prefs.setString('skippedUpdate', release.version);
  if (choice == 'download') await launchUrl(Uri.parse(release.downloadUrl ?? release.pageUrl));
}
