import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cards/env.dart';
import '../ha/history.dart';
import '../ha/states.dart';
import '../util/fmt.dart';
import 'info_shell.dart';
import 'theme.dart';

/// A sensor on a graph: which, what to call it, how to show its value, and
/// the colour of its line.
class GraphItem {
  const GraphItem({required this.entity, required this.name, required this.color, this.unit, this.decimals});
  final String entity;
  final String name;
  final Color color;
  final String? unit;
  final int? decimals;
}

/// Up to four lines on one graph. The first takes the card's accent, then
/// amber, green and violet - unless an item names its own colour.
const graphMax = 4;
const _palette = [Ns.gold, Ns.mint, Ns.violet];
Color graphColour(Color? own, int i, Color accent) => own ?? (i == 0 ? accent : _palette[(i - 1) % _palette.length]);

/// The value text for an item, and the number behind it (null when it has none).
(String, String, double?) graphValue(HaStates states, GraphItem it) {
  final s = states.get(it.entity);
  final broken = s == null || s.isBroken;
  final n = broken ? null : s.numeric?.toDouble();
  final unit = it.unit ?? s?.unit ?? '';
  final text = broken ? '—' : (n == null ? s.state : fmt(n, it.decimals));
  return (text, n == null ? '' : unit, n);
}

/// Grid, bands and lines, in one paint behind a RepaintBoundary: a swipe moves
/// the finished picture and never repaints it. Repainted only when the layout
/// object changes - new data or a new live value - never per frame.
class _GraphPainter extends CustomPainter {
  _GraphPainter(this.layout, this.colours, this.stroke);
  final GraphLayout layout;
  final List<Color> colours;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final grid = Paint()
      ..color = const Color(0x16FFFFFF)
      ..strokeWidth = 1;
    for (final t in layout.yTicks) {
      final y = (t.f * h).roundToDouble() + .5;
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
    for (final t in layout.xTicks) {
      final x = (t.f * w).roundToDouble() + .5;
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    // every band before any line, so no band covers another sensor's line
    for (var i = 0; i < layout.lines.length; i++) {
      final b = layout.lines[i].band;
      if (b.length < 2) continue;
      final path = Path()..moveTo(b.first.$1 * w, b.first.$2 * h);
      for (final p in b.skip(1)) {
        path.lineTo(p.$1 * w, p.$2 * h);
      }
      for (final p in b.reversed) {
        path.lineTo(p.$1 * w, p.$3 * h);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = colours[i].withValues(alpha: .16));
    }
    for (var i = 0; i < layout.lines.length; i++) {
      final l = layout.lines[i].line;
      if (l.isEmpty) continue;
      final path = Path()..moveTo(l.first.$1 * w, l.first.$2 * h);
      for (final p in l.skip(1)) {
        path.lineTo(p.$1 * w, p.$2 * h);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colours[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) => !identical(old.layout, layout) || old.colours != colours;
}

const _labelStyle = TextStyle(
  color: Ns.muted,
  fontSize: 11,
  height: 1,
  fontFeatures: Ns.tabular,
  shadows: [Shadow(color: Ns.surface, blurRadius: 3), Shadow(color: Ns.surface, blurRadius: 3)],
);

/// The plot: the painting, and the value labels over it. Each value sits just
/// above its line, the top one just under its own so it stays inside; labels
/// need ~18 px, so where lines are closer only every other one keeps its
/// value (always the top), and one that would crowd the top value gives way.
class GraphPlot extends StatelessWidget {
  const GraphPlot({
    super.key,
    required this.layout,
    required this.colours,
    this.stroke = 2.5,
    this.labelSize = 11,
    this.hideBottomLabel = false,
  });
  final GraphLayout layout;
  final List<Color> colours;
  final double stroke;
  final double labelSize;

  /// In a card the graph is short, and its edge already says where the
  /// bottom is.
  final bool hideBottomLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      final ticks = layout.yTicks;
      final gap = h / (ticks.length - 1).clamp(1, 99);
      final every = (18 / gap).ceil().clamp(1, 99);
      final style = _labelStyle.copyWith(fontSize: labelSize);
      return Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _GraphPainter(layout, colours, stroke)),
            ),
          ),
          for (var i = 0; i < ticks.length; i++)
            if (_shown(i, ticks.length, every, gap))
              Positioned(
                left: 8,
                // above the line; the top one under it
                top: i == ticks.length - 1
                    ? ticks[i].f * h + labelSize * .25
                    : ticks[i].f * h - labelSize * 1.25,
                child: Text(ticks[i].label, style: style),
              ),
        ],
      );
    });
  }

  bool _shown(int i, int count, int every, double gap) {
    if (hideBottomLabel && i == 0) return false;
    final fromTop = count - 1 - i;
    if (fromTop % every != 0) return false;
    return !(fromTop == every && every * gap < 34);
  }
}

/// The time labels under the full-screen graph.
class GraphTimes extends StatelessWidget {
  const GraphTimes({super.key, required this.ticks});
  final List<Tick> ticks;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 16,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            clipBehavior: Clip.none,
            children: [
              for (final t in ticks)
                Positioned(
                  left: t.f * box.maxWidth - 20,
                  width: 40,
                  child: Text(t.label,
                      textAlign: TextAlign.center, style: _labelStyle.copyWith(fontSize: 12, shadows: const [])),
                ),
            ],
          ),
        ),
      );
}

const graphRanges = [(6, '6 h'), (24, '24 h'), (72, '3 d'), (168, '7 d')];

String graphLabel(int hours) {
  for (final (h, l) in graphRanges) {
    if (h == hours) return l;
  }
  return hours % 24 == 0 ? '${hours ~/ 24} d' : '$hours h';
}

/// The full-screen graph a long-press opens, from the graph card, a sensor
/// card or one reading of a sensors card: bigger, with 6 h / 24 h / 3 d / 7 d.
/// It asks HA for data when it opens and when the range changes, and follows
/// the live values while open. The X or a tap outside closes it.
Future<void> showGraphView(
  BuildContext context, {
  required PanelEnv env,
  required List<GraphItem> items,
  String? title,
  int hours = 24,
  bool? band,
}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: Ns.ground.withValues(alpha: .82),
    transitionDuration: const Duration(milliseconds: 160),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (_, _, _) => _GraphView(
      env: env,
      items: items.take(graphMax).toList(),
      title: title,
      hours: graphRanges.any((r) => r.$1 == hours) ? hours : 24,
      band: band ?? items.length == 1,
    ),
  );
}

class _GraphView extends StatefulWidget {
  const _GraphView({required this.env, required this.items, required this.title, required this.hours, required this.band});
  final PanelEnv env;
  final List<GraphItem> items;
  final String? title;
  final int hours;
  final bool band;

  @override
  State<_GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<_GraphView> {
  late int _hours = widget.hours;
  GraphSeries? _series;
  bool _failed = false;
  int _ask = 0;

  List<GraphItem> get items => widget.items;
  List<Color> get colours => [for (final it in items) it.color];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ask = ++_ask;
    setState(() {
      _series = null;
      _failed = false;
    });
    try {
      final s = await fetchSeries(widget.env.conn, [for (final it in items) it.entity], _hours);
      if (mounted && ask == _ask) setState(() => _series = s);
    } catch (_) {
      if (mounted && ask == _ask) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = widget.env;
    final single = items.length == 1;
    return AnimatedBuilder(
      animation: Listenable.merge([for (final it in items) env.states.listen(it.entity)]),
      builder: (context, _) {
        final values = [for (final it in items) graphValue(env.states, it)];
        final layout = _series == null
            ? null
            : GraphLayout.of(_series!, _hours, [for (var i = 0; i < items.length; i++) (items[i].entity, values[i].$3)],
                band: widget.band);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              color: Ns.surface,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.title ?? (single ? items.first.name : ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Ns.muted, fontSize: 18, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              if (single) ...[
                                BigValue(values.first.$1, unit: values.first.$2, size: 44),
                                if (layout != null) ...[
                                  const SizedBox(height: 6),
                                  Text('↑ ${fmt(layout.hi, items.first.decimals)}   ↓ ${fmt(layout.lo, items.first.decimals)}',
                                      style: const TextStyle(color: Ns.muted, fontSize: 14, fontFeatures: Ns.tabular)),
                                ],
                              ] else
                                Wrap(
                                  spacing: 18,
                                  runSpacing: 4,
                                  children: [
                                    for (var i = 0; i < items.length; i++)
                                      GraphReading(text: values[i].$1, unit: values[i].$2, name: items[i].name,
                                          color: items[i].color, size: 26),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        _Square(
                          onTap: () => Navigator.of(context).pop(),
                          child: const Icon(Icons.close, color: Ns.text, size: 26),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: ColoredBox(
                          color: const Color(0x08FFFFFF),
                          child: layout != null
                              ? GraphPlot(layout: layout, colours: colours, stroke: 3, labelSize: 12)
                              : Center(
                                  child: Text(
                                      _failed || _series != null ? 'Home Assistant has no history for this' : 'Loading…',
                                      style: const TextStyle(color: Ns.muted, fontSize: 15))),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GraphTimes(ticks: layout?.xTicks ?? const []),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final (h, label) in graphRanges) ...[
                          if (h != graphRanges.first.$1) const SizedBox(width: 10),
                          Expanded(
                            child: _Square(
                              height: 52,
                              color: h == _hours ? items.first.color : const Color(0x14FFFFFF),
                              onTap: () {
                                if (h == _hours) return;
                                HapticFeedback.lightImpact();
                                _hours = h;
                                _load();
                              },
                              child: Text(label,
                                  style: TextStyle(
                                      color: h == _hours ? Ns.ground : Ns.text,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A value with its name and its line's colour - the several-sensors header.
class GraphReading extends StatelessWidget {
  const GraphReading({super.key, required this.text, required this.unit, required this.name, required this.color, this.size = 30});
  final String text, unit, name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          BigValue(text, unit: unit, size: size),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Ns.muted, fontSize: 13)),
          ]),
        ],
      );
}

class _Square extends StatelessWidget {
  const _Square({required this.onTap, required this.child, this.height = 56, this.color = const Color(0x1AFFFFFF)});
  final VoidCallback onTap;
  final Widget child;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: height == 56 ? 56 : null,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height == 56 ? 16 : 14)),
          child: child,
        ),
      );
}
