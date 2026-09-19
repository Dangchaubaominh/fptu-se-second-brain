import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/vault_index.dart';
import '../state/providers.dart';
import 'widgets.dart';

class _Layout {
  _Layout(this.ids, this.pos, this.edges, this.degree);
  final List<String> ids;
  final List<Offset> pos;
  final List<(int, int)> edges;
  final List<int> degree;
}

const _canvas = Size(2400, 1800);

/// Fruchterman–Reingold force-directed layout (deterministic seed so the
/// graph doesn't jump around between rebuilds).
_Layout _computeLayout(VaultIndex index, {required bool coursesOnly}) {
  final ids = index.notes.values
      .where((n) => !coursesOnly || n.isCourse)
      .map((n) => n.path)
      .toList()
    ..sort();
  final at = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  final edges = <(int, int)>{};
  for (final e in index.outgoing.entries) {
    final a = at[e.key];
    if (a == null) continue;
    for (final t in e.value) {
      final b = at[t];
      if (b != null && a != b) edges.add(a < b ? (a, b) : (b, a));
    }
  }
  final n = ids.length;
  final degree = List.filled(n, 0);
  for (final (a, b) in edges) {
    degree[a]++;
    degree[b]++;
  }
  final rnd = Random(42);
  final pos = List.generate(
      n, (_) => Offset(_canvas.width * (0.3 + rnd.nextDouble() * 0.4), _canvas.height * (0.3 + rnd.nextDouble() * 0.4)));
  if (n == 0) return _Layout(ids, pos, edges.toList(), degree);

  final k = sqrt(_canvas.width * _canvas.height / n) * 0.45;
  var temp = _canvas.width / 8;
  final center = Offset(_canvas.width / 2, _canvas.height / 2);
  for (var iter = 0; iter < 300; iter++) {
    final disp = List.filled(n, Offset.zero);
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var d = pos[i] - pos[j];
        var dist = d.distance;
        if (dist < 0.01) {
          d = Offset(rnd.nextDouble() - 0.5, rnd.nextDouble() - 0.5);
          dist = 0.01;
        }
        final f = d / dist * (k * k / dist);
        disp[i] += f;
        disp[j] -= f;
      }
    }
    for (final (a, b) in edges) {
      final d = pos[a] - pos[b];
      final dist = max(d.distance, 0.01);
      final f = d / dist * (dist * dist / k);
      disp[a] -= f;
      disp[b] += f;
    }
    for (var i = 0; i < n; i++) {
      disp[i] += (center - pos[i]) * 0.02 * (degree[i] == 0 ? 3 : 1); // gravity keeps orphans close
      final len = disp[i].distance;
      if (len > 0) pos[i] += disp[i] / len * min(len, temp);
      pos[i] = Offset(pos[i].dx.clamp(40, _canvas.width - 40), pos[i].dy.clamp(40, _canvas.height - 40));
    }
    temp *= 0.985;
  }
  return _Layout(ids, pos, edges.toList(), degree);
}

class GraphPage extends ConsumerStatefulWidget {
  const GraphPage({super.key});

  @override
  ConsumerState<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends ConsumerState<GraphPage> {
  final _tc = TransformationController();
  VaultIndex? _layoutFor;
  bool _layoutCoursesOnly = false;
  _Layout? _layout;
  bool _coursesOnly = false;
  int? _hover;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  int? _hit(Offset p) {
    final l = _layout!;
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < l.pos.length; i++) {
      final d = (l.pos[i] - p).distance;
      if (d < _radius(l.degree[i]) + 6 && d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  static double _radius(int degree) => 5 + sqrt(degree) * 3;

  void _fit(Size viewport) {
    final s = min(viewport.width / _canvas.width, viewport.height / _canvas.height);
    _tc.value = Matrix4.identity()
      ..translateByDouble((viewport.width - _canvas.width * s) / 2, (viewport.height - _canvas.height * s) / 2, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(vaultProvider).value;
    if (index == null) return const SizedBox();
    if (!identical(_layoutFor, index) || _layoutCoursesOnly != _coursesOnly) {
      _layout = _computeLayout(index, coursesOnly: _coursesOnly);
      _layoutFor = index;
      _layoutCoursesOnly = _coursesOnly;
      _hover = null;
    }
    final layout = _layout!;
    final scheme = Theme.of(context).colorScheme;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Graph view',
        subtitle: '${layout.ids.length} note · ${layout.edges.length} liên kết. Cuộn để zoom, kéo để di chuyển, bấm vào nút để mở note.',
        actions: [
          FilterChip(
            label: const Text('Chỉ môn học'),
            selected: _coursesOnly,
            onSelected: (v) => setState(() => _coursesOnly = v),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Wrap(spacing: 16, children: [
          _Legend(color: scheme.primary, label: 'Môn học'),
          _Legend(color: scheme.tertiary, label: 'Khái niệm'),
          _Legend(color: scheme.outline, label: 'Ghi chú khác'),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: layout.ids.isEmpty
            ? const EmptyState(icon: Icons.hub_outlined, title: 'Chưa có dữ liệu để vẽ graph')
            : LayoutBuilder(builder: (context, c) {
                if (_tc.value.isIdentity()) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _fit(c.biggest));
                }
                return ClipRect(
                  child: InteractiveViewer(
                    transformationController: _tc,
                    constrained: false,
                    minScale: 0.1,
                    maxScale: 4,
                    boundaryMargin: const EdgeInsets.all(800),
                    child: MouseRegion(
                      onHover: (e) {
                        final h = _hit(e.localPosition);
                        if (h != _hover) setState(() => _hover = h);
                      },
                      cursor: _hover == null ? MouseCursor.defer : SystemMouseCursors.click,
                      child: GestureDetector(
                        onTapUp: (e) {
                          final h = _hit(e.localPosition);
                          if (h != null) openNote(ref, layout.ids[h]);
                        },
                        child: CustomPaint(
                          size: _canvas,
                          painter: _GraphPainter(layout, index, _hover, scheme, _tc),
                        ),
                      ),
                    ),
                  ),
                );
              }),
      ),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.l, this.index, this.hover, this.scheme, this.tc) : super(repaint: tc);
  final _Layout l;
  final VaultIndex index;
  final int? hover;
  final ColorScheme scheme;
  final TransformationController tc;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = tc.value.getMaxScaleOnAxis();
    final neighbors = <int>{};
    if (hover != null) {
      for (final (a, b) in l.edges) {
        if (a == hover) neighbors.add(b);
        if (b == hover) neighbors.add(a);
      }
    }
    final dim = hover != null;
    final edgePaint = Paint()..strokeWidth = 1;
    for (final (a, b) in l.edges) {
      final active = a == hover || b == hover;
      edgePaint.color = active
          ? scheme.primary.withValues(alpha: 0.9)
          : scheme.outline.withValues(alpha: dim ? 0.08 : 0.35);
      edgePaint.strokeWidth = active ? 2 : 1;
      canvas.drawLine(l.pos[a], l.pos[b], edgePaint);
    }
    for (var i = 0; i < l.ids.length; i++) {
      final note = index.notes[l.ids[i]]!;
      final base = note.isCourse
          ? scheme.primary
          : note.frontmatter['type'] == 'concept'
              ? scheme.tertiary
              : scheme.outline;
      final faded = dim && i != hover && !neighbors.contains(i);
      final r = _GraphPageState._radius(l.degree[i]);
      canvas.drawCircle(l.pos[i], r, Paint()..color = faded ? base.withValues(alpha: 0.2) : base);
      if (i == hover) {
        canvas.drawCircle(l.pos[i], r + 3, Paint()
          ..color = scheme.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
      // Show labels when zoomed in, for hubs, or around the hovered node.
      final showLabel = i == hover || neighbors.contains(i) || (!dim && (scale > 0.6 || l.degree[i] >= 4));
      if (!showLabel) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: note.isCourse ? note.courseCode : note.title,
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: faded ? 0.3 : 0.9),
            fontSize: (i == hover ? 14 : 11) / scale.clamp(0.5, 1.5),
            fontWeight: i == hover ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 220);
      tp.paint(canvas, l.pos[i] + Offset(-tp.width / 2, r + 3));
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.l != l || old.hover != hover || old.scheme != scheme;
}
