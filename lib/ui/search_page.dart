import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'widgets.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final _ctrl = TextEditingController(text: ref.read(searchQueryProvider));
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(searchQueryProvider, (_, q) {
      if (_ctrl.text != q) _ctrl.text = q;
    });
    ref.listen(pageProvider, (_, p) {
      if (p == AppPage.search) _focus.requestFocus();
    });
    final index = ref.watch(vaultProvider).value;
    if (index == null) return const SizedBox();
    final query = ref.watch(searchQueryProvider);
    final hits = index.search(query);
    final tags = index.tagCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Tìm kiếm',
          subtitle: 'Tìm không dấu vẫn ra ("con tro" → "Con trỏ"). Gõ #tag để lọc theo tag. Phím tắt: Ctrl+K',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            autofocus: true,
            onChanged: (v) => ref.read(searchQueryProvider.notifier).set(v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Tìm trong ${index.notes.length} ghi chú…',
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => ref.read(searchQueryProvider.notifier).set(''),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in tags.take(24))
                FilterChip(
                  label: Text('#${t.key} · ${t.value}'),
                  selected: query == '#${t.key}',
                  onSelected: (_) => ref.read(searchQueryProvider.notifier).set('#${t.key}'),
                ),
            ],
          ),
        ),
        if (query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: Text('${hits.length} kết quả', style: theme.textTheme.labelMedium),
          ),
        Expanded(
          child: query.isEmpty
              ? const EmptyState(icon: Icons.manage_search, title: 'Nhập từ khóa để tìm trong vault')
              : hits.isEmpty
              ? const EmptyState(icon: Icons.search_off, title: 'Không tìm thấy kết quả')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: hits.length,
                  separatorBuilder: (_, _) => const Divider(indent: 12, endIndent: 12),
                  itemBuilder: (_, i) {
                    final h = hits[i];
                    final s = h.snippet;
                    final hasMatch = h.matchEnd > h.matchStart && h.matchEnd <= s.length;
                    return ListTile(
                      leading: Icon(h.note.isCourse ? Icons.school_outlined : Icons.description_outlined),
                      title: Text(h.note.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h.note.path,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: hasMatch ? s.substring(0, h.matchStart) : s),
                                if (hasMatch)
                                  TextSpan(
                                    text: s.substring(h.matchStart, h.matchEnd),
                                    style: TextStyle(
                                      backgroundColor: theme.colorScheme.primaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                if (hasMatch) TextSpan(text: s.substring(h.matchEnd)),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      onTap: () => openNote(ref, h.note.path),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
