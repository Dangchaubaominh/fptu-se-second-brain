import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/markdown_utils.dart';
import '../state/providers.dart';

/// Opens a wikilink target, creating the note if it doesn't exist (like Obsidian).
Future<void> followWikilink(WidgetRef ref, String target) async {
  final index = ref.read(vaultProvider).value;
  if (index == null) return;
  final name = target.split('#').first;
  final path = index.resolve(name) ?? (await ref.read(vaultProvider.notifier).create('', name)).path;
  openNote(ref, path);
}

class NotePreview extends ConsumerWidget {
  const NotePreview({super.key, required this.content, this.padding = const EdgeInsets.all(24)});
  final String content;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fm = splitFrontmatter(content);

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fm.data.isNotEmpty) ...[_Properties(data: fm.data), const SizedBox(height: 16)],
          MarkdownBody(
            data: obsidianToMarkdown(fm.body),
            selectable: true,
            onTapLink: (text, href, title) {
              if (href == null) return;
              if (href.startsWith('wikilink:')) {
                followWikilink(ref, Uri.decodeComponent(href.substring(9)));
              } else {
                final uri = Uri.tryParse(href);
                if (uri != null) launchUrl(uri);
              }
            },
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              h1: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              h2: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              code: TextStyle(fontFamily: 'Consolas', backgroundColor: scheme.surfaceContainerHighest, fontSize: 13),
              codeblockDecoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              blockquoteDecoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                border: Border(left: BorderSide(color: scheme.primary, width: 4)),
              ),
              a: TextStyle(
                color: scheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: scheme.primary,
              ),
              tableBorder: TableBorder.all(color: scheme.outlineVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Properties extends StatelessWidget {
  const _Properties({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          for (final e in data.entries)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${e.key}: ',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: e.value is List ? (e.value as List).join(', ') : '${e.value ?? ''}',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
