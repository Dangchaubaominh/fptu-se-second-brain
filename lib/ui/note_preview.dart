import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
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
  const NotePreview({super.key, required this.content, this.padding = const EdgeInsets.all(24), this.notePath});
  final String content;
  final EdgeInsets padding;

  /// Used to resolve relative image paths like `![](img/a.png)`.
  final String? notePath;

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
            imageBuilder: (uri, title, alt) => _VaultImage(uri: uri, alt: alt, notePath: notePath),
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

/// Renders `![[img.png]]` and `![](path)` from the vault, or remote http(s) images.
class _VaultImage extends ConsumerWidget {
  const _VaultImage({required this.uri, this.alt, this.notePath});
  final Uri uri;
  final String? alt;
  final String? notePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = double.tryParse(alt ?? '');
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return Image.network(uri.toString(), width: width, errorBuilder: (_, _, _) => _missing(context, uri.toString()));
    }
    final index = ref.watch(vaultProvider).value;
    final target = Uri.decodeComponent(uri.scheme == 'vaultimg' ? uri.path : uri.toString());
    final folder = notePath == null ? '' : p.posix.dirname(notePath!).replaceFirst(RegExp(r'^\.$'), '');
    final rel = index?.resolveAttachment(target, fromFolder: folder);
    if (index == null || rel == null) return _missing(context, target);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(p.joinAll([index.root, ...rel.split('/')])),
          width: width,
          errorBuilder: (_, _, _) => _missing(context, target),
        ),
      ),
    );
  }

  Widget _missing(BuildContext context, String name) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(6)),
      child: Text('🖼 Không tìm thấy ảnh: $name', style: TextStyle(color: scheme.onErrorContainer)),
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
