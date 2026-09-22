import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/review_stats.dart';
import '../state/providers.dart';

const _weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

String _date(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day}/${d.month}';

/// Review statistics: KPI tiles, a calendar heatmap and a 7-day forecast.
class ReviewStatsView extends ConsumerWidget {
  const ReviewStatsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(reviewStatsProvider);
    final theme = Theme.of(context);
    final retention = stats.retention30;

    Widget card(String title, Widget child, {String? caption}) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            if (caption != null)
              Text(caption, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Thống kê', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Tile(label: 'Chuỗi ngày ôn', value: '${stats.streak}', unit: 'ngày', icon: Icons.local_fire_department),
              _Tile(label: 'Đã ôn hôm nay', value: '${stats.reviewsToday}', unit: 'lượt', icon: Icons.today),
              _Tile(
                label: 'Tỉ lệ nhớ (30 ngày)',
                value: retention == null ? '—' : '${(retention * 100).round()}',
                unit: retention == null ? 'chưa đủ dữ liệu' : '%',
                icon: Icons.psychology,
              ),
              _Tile(
                label: 'Mới · Đang học · Thuộc lâu',
                value: '${stats.newCards} · ${stats.learningCards} · ${stats.matureCards}',
                unit: 'thẻ',
                icon: Icons.style,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final heat = card(
                'Lượt ôn mỗi ngày',
                _Heatmap(perDay: stats.perDay),
                caption: '20 tuần gần nhất · di chuột lên ô để xem chi tiết',
              );
              final forecast = card(
                'Thẻ đến hạn 7 ngày tới',
                _Forecast(counts: stats.forecast),
                caption: 'Tổng ${stats.forecast.fold(0, (s, x) => s + x)} thẻ · thẻ quá hạn tính vào hôm nay',
              );
              if (c.maxWidth < 900) return Column(children: [heat, const SizedBox(height: 12), forecast]);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: heat),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: forecast),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.unit, required this.icon});
  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: value,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: ' $unit',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// GitHub-style calendar: one column per week (Mon→Sun), single-hue ramp.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.perDay});
  final Map<DateTime, int> perDay;

  static const _weeks = 20;
  static const _cell = 13.0;
  static const _gap = 3.0;

  /// Sequential steps: none, then 4 levels of the primary hue.
  static int _level(int n) => n == 0 ? 0 : (n < 5 ? 1 : (n < 15 ? 2 : (n < 30 ? 3 : 4)));

  static Color _color(int level, ColorScheme s) =>
      level == 0 ? s.surfaceContainerHighest : Color.alphaBlend(s.primary.withValues(alpha: 0.25 * level), s.surface);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = dayOf(DateTime.now());
    final thisMonday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final start = DateTime(thisMonday.year, thisMonday.month, thisMonday.day - 7 * (_weeks - 1));
    final muted = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    Widget cell(DateTime d) {
      if (d.isAfter(today)) return const SizedBox(width: _cell, height: _cell);
      final n = perDay[d] ?? 0;
      return Tooltip(
        message: '${_date(d)}: $n lượt ôn',
        waitDuration: const Duration(milliseconds: 150),
        child: Container(
          width: _cell,
          height: _cell,
          decoration: BoxDecoration(
            color: _color(_level(n), scheme),
            borderRadius: BorderRadius.circular(3),
            border: d == today ? Border.all(color: scheme.onSurface, width: 1.5) : null,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  const SizedBox(height: 16),
                  for (var r = 0; r < 7; r++)
                    SizedBox(
                      height: _cell + _gap,
                      width: 24,
                      child: r.isEven ? Text(_weekdays[r], style: muted) : null,
                    ),
                ],
              ),
              for (var w = 0; w < _weeks; w++)
                Padding(
                  padding: const EdgeInsets.only(right: _gap),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 16,
                        width: _cell,
                        child: OverflowBox(
                          maxWidth: 40,
                          alignment: Alignment.centerLeft,
                          child: Builder(
                            builder: (_) {
                              final monday = DateTime(start.year, start.month, start.day + 7 * w);
                              final isNewMonth = w == 0 || monday.day <= 7;
                              return isNewMonth ? Text('Th${monday.month}', style: muted) : const SizedBox();
                            },
                          ),
                        ),
                      ),
                      for (var r = 0; r < 7; r++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _gap),
                          child: cell(DateTime(start.year, start.month, start.day + 7 * w + r)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ít', style: muted),
            const SizedBox(width: 6),
            for (var l = 0; l <= 4; l++)
              Container(
                width: _cell,
                height: _cell,
                margin: const EdgeInsets.only(right: _gap),
                decoration: BoxDecoration(color: _color(l, scheme), borderRadius: BorderRadius.circular(3)),
              ),
            const SizedBox(width: 3),
            Text('Nhiều', style: muted),
          ],
        ),
      ],
    );
  }
}

/// Single-series bar chart: thin bars, rounded tops, tooltip per bar,
/// direct label only on today.
class _Forecast extends StatelessWidget {
  const _Forecast({required this.counts});
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = dayOf(DateTime.now());
    final peak = max(1, counts.fold(0, max));
    final muted = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    const plotHeight = 110.0;

    return Column(
      children: [
        SizedBox(
          height: plotHeight + 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < counts.length; i++)
                Expanded(
                  child: Tooltip(
                    message: '${i == 0 ? 'Hôm nay' : _date(today.add(Duration(days: i)))}: ${counts[i]} thẻ đến hạn',
                    waitDuration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (i == 0) Text('${counts[0]}', style: theme.textTheme.labelMedium),
                          const SizedBox(height: 2),
                          Container(
                            height: counts[i] == 0 ? 2 : max(4, plotHeight * counts[i] / peak),
                            decoration: BoxDecoration(
                              color: counts[i] == 0 ? scheme.outlineVariant : scheme.primary,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(color: scheme.outlineVariant, height: 1),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < counts.length; i++)
              Expanded(
                child: Text(
                  i == 0 ? 'Nay' : _weekdays[today.add(Duration(days: i)).weekday - 1],
                  textAlign: TextAlign.center,
                  style: muted,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
