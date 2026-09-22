import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/claude_client.dart';
import '../core/update_checker.dart';
import '../state/providers.dart';
import 'update_dialog.dart';
import 'welcome_page.dart';
import 'widgets.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final _key = TextEditingController(text: ref.read(settingsProvider).apiKey);
  bool _obscure = true;
  String? _testResult;
  bool _testing = false;
  bool _checking = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    await ref.read(settingsProvider.notifier).setApiKey(_key.text);
    final key = ref.read(settingsProvider).effectiveApiKey;
    if (key.isEmpty) {
      setState(() => _testResult = 'Chưa có API key.');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final client = ClaudeClient(key);
    try {
      final buf = StringBuffer();
      await for (final t in client.streamText(
        system: 'Trả lời ngắn gọn.',
        messages: [(role: 'user', content: 'Chào bằng một câu tiếng Việt.')],
        maxTokens: 200,
      )) {
        buf.write(t);
      }
      _testResult = '✅ Kết nối thành công: ${buf.toString().trim()}';
    } catch (e) {
      _testResult = '❌ $e';
    } finally {
      client.close();
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final fromEnv = settings.apiKey.isEmpty && settings.effectiveApiKey.isNotEmpty;

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );

    return ListView(
      children: [
        const PageHeader(title: 'Cài đặt'),
        section('Vault', [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(settings.vaultPath ?? '—'),
            subtitle: const Text('Mở chính thư mục này bằng Obsidian ("Open folder as vault") để dùng song song.'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => pickVault(ref),
                icon: const Icon(Icons.folder_open),
                label: const Text('Đổi vault'),
              ),
              OutlinedButton.icon(
                onPressed: () => createSampleVault(context, ref),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Tạo vault mẫu FPTU SE'),
              ),
              TextButton(
                onPressed: () => ref.read(settingsProvider.notifier).setVaultPath(null),
                child: const Text('Đóng vault'),
              ),
            ],
          ),
        ]),
        section('Trợ lý AI (Claude)', [
          Text(
            'Model: ${ClaudeClient.model}. Lấy API key tại console.anthropic.com. '
            'Key được lưu cục bộ trên máy này (SharedPreferences), không ghi vào vault.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Anthropic API key',
              hintText: fromEnv ? 'Đang dùng biến môi trường ANTHROPIC_API_KEY' : 'sk-ant-…',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (v) => ref.read(settingsProvider.notifier).setApiKey(v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: () async {
                  await ref.read(settingsProvider.notifier).setApiKey(_key.text);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu API key')));
                  }
                },
                child: const Text('Lưu'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _testing ? null : _test, child: const Text('Kiểm tra kết nối')),
              if (_testing)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
          if (_testResult != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_testResult!)),
        ]),
        section('Giao diện', [
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Theo hệ thống')),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Sáng')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Tối')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => ref.read(settingsProvider.notifier).setThemeMode(s.first),
          ),
        ]),
        section('Phiên bản', [
          Row(
            children: [
              Expanded(
                child: Text(
                  'FPTU SE Second Brain ${ref.watch(appVersionProvider).value ?? ''}\n'
                  'Bản mới được phát hành tại github.com/$githubRepo/releases',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _checking
                    ? null
                    : () async {
                        setState(() => _checking = true);
                        await checkForUpdates(context, ref, manual: true);
                        if (mounted) setState(() => _checking = false);
                      },
                icon: _checking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.system_update_alt),
                label: const Text('Kiểm tra cập nhật'),
              ),
            ],
          ),
        ]),
        section('Phím tắt', const [
          Text(
            'Ctrl+O  Mở nhanh note (quick switcher)\nCtrl+K  Tìm kiếm\nCtrl+G  Graph view\nCtrl+S  Lưu note (app cũng tự lưu sau 0,7 giây)\n'
            'Ôn tập: Space lật thẻ · 1–4 chấm điểm · Esc dừng',
          ),
        ]),
      ],
    );
  }
}
