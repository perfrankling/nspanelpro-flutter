import 'dart:async';

import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/connection.dart';
import '../ha/history.dart';
import '../ha/states.dart';
import '../ui/graph.dart';
import '../ui/info_shell.dart';
import '../ui/page_scope.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/fmt.dart';
import 'env.dart';

/// A sensor's last hours - or up to four sensors' on one scale - from Home
/// Assistant's statistics, as the web graph card draws them: the mean per
/// five minutes as a line, the min to max as a band (one sensor by default),
/// gridlines at round values and times. Asked for only while the card is on
/// screen ([PageScope]), again every five minutes, the recorder's own cadence;
/// in between, the end of each line follows the live value. Long-press opens
/// the same graph full-screen.
class GraphCard extends StatefulWidget {
  const GraphCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<GraphCard> createState() => _GraphCardState();
}

class _GraphCardState extends State<GraphCard> {
  CardConfig get c => widget.config;
  PageScope? _scope;
  Listenable? _changes;
  GraphSeries? _series;
  bool _failed = false;
  bool _fetching = false;
  Timer? _next;
  int _fails = 0;

  bool get _active => _scope?.active ?? true;
  int get _hours => c.intOr('hours', 24).clamp(1, 168);

  /// `entity` for one sensor, `entities` for up to four: "sensor.x" or
  /// {entity, name, color}. unit and decimals are the card's.
  List<GraphItem> get _items {
    final list = c['entities'] is List && c.listOr('entities').isNotEmpty
        ? c.maps('entities')
        : [if (c.str('entity') != null) {'entity': c.str('entity')}];
    final accent = parseHex(c.str('accent')) ?? Ns.sky;
    final out = <GraphItem>[];
    for (final it in list) {
      final id = it.str('entity');
      if (id == null || out.length == graphMax) continue;
      out.add(GraphItem(
        entity: id,
        name: it.str('name') ?? (list.length == 1 ? c.titleOr(friendlyName(widget.env.states.get(id), id))
            : friendlyName(widget.env.states.get(id), id)),
        color: graphColour(parseHex(it.str('color')), out.length, accent),
        unit: c.str('unit'),
        decimals: c['decimals'] as int?,
      ));
    }
    return out;
  }

  /// The min-max band: on for one sensor, off behind several, where the bands
  /// would overlap into a smudge - unless show_minmax says otherwise.
  bool _band(int count) => c['show_minmax'] is bool ? c['show_minmax'] as bool : count == 1;

  // The dashboard is drawn from its cached config before Home Assistant has
  // answered, so the first request can go out before the connection is up.
  // When it comes up, a card still without a graph asks again at once.
  @override
  void initState() {
    super.initState();
    widget.env.conn.status.addListener(_online);
  }

  void _online() {
    if (widget.env.conn.status.value != HaStatus.online || _series != null || _fetching) return;
    _next?.cancel();
    _next = null;
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = PageScope.maybeOf(context);
    if (!identical(scope, _scope)) {
      _changes?.removeListener(_sync);
      _scope = scope;
      _changes = scope?.changes;
      _changes?.addListener(_sync);
    }
    _sync();
  }

  @override
  void dispose() {
    widget.env.conn.status.removeListener(_online);
    _changes?.removeListener(_sync);
    _next?.cancel();
    super.dispose();
  }

  /// On screen: fetch, unless what it has is under five minutes old. Off
  /// screen: stop, and keep the last graph so the page does not come back
  /// empty.
  void _sync() {
    if (!mounted) return;
    if (!_active) {
      _next?.cancel();
      _next = null;
      return;
    }
    if (_fetching || _next != null) return;
    final age = _series == null ? null : DateTime.now().millisecondsSinceEpoch - _series!.end;
    if (age != null && age < 300000) {
      _next = Timer(Duration(milliseconds: 300000 - age), _fetch);
    } else {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    _next = null;
    if (!mounted || !_active || _fetching) return;
    final items = _items;
    if (items.isEmpty) return;
    _fetching = true;
    try {
      final s = await fetchSeries(widget.env.conn, [for (final it in items) it.entity], _hours);
      if (mounted) {
        setState(() {
          _series = s;
          _failed = false;
        });
      }
      _fails = 0;
    } catch (_) {
      // "No history" only when HA itself answered; not connected yet is not
      // an answer, and the status listener asks again when it is
      final online = widget.env.conn.status.value == HaStatus.online;
      if (mounted && online) setState(() => _failed = true);
      _fails++;
    } finally {
      _fetching = false;
      // after a failure: 10 s, 20 s, 40 s ... up to the usual five minutes
      final wait = _fails == 0
          ? const Duration(minutes: 5)
          : Duration(seconds: (10 << (_fails - 1).clamp(0, 5)).clamp(10, 300));
      if (mounted && _active) _next = Timer(wait, _fetch);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final env = widget.env;
    final height = c.numOr('height', 200);
    return AnimatedBuilder(
      animation: Listenable.merge([for (final it in items) env.states.listen(it.entity)]),
      builder: (context, _) {
        final values = [for (final it in items) graphValue(env.states, it)];
        final single = items.length == 1;
        final layout = _series == null
            ? null
            : GraphLayout.of(_series!, _hours, [for (var i = 0; i < items.length; i++) (items[i].entity, values[i].$3)],
                band: _band(items.length));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: c.str('long_press') == 'none' || items.isEmpty
              ? null
              : () => showGraphView(context,
                  env: env,
                  items: items,
                  title: c.str('title') ?? c.str('name'),
                  hours: _hours,
                  band: _band(items.length)),
          child: InfoShell(
            height: height,
            accent: items.isEmpty ? Ns.sky : items.first.color,
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                // the graph across the bottom, under the header
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  top: 84,
                  child: layout != null
                      ? GraphPlot(layout: layout, colours: [for (final it in items) it.color], hideBottomLabel: true)
                      : (_failed || _series != null)
                          ? const Center(
                              child: Text('No history from Home Assistant',
                                  style: TextStyle(color: Ns.muted, fontSize: 14)))
                          : const SizedBox.shrink(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: single
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  BigValue(values.first.$1, unit: values.first.$2, size: 40),
                                  const SizedBox(height: 4),
                                  Text(items.first.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Ns.muted, fontSize: 13)),
                                ],
                              )
                            : Row(
                                children: [
                                  for (var i = 0; i < items.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 18),
                                    Flexible(
                                      child: GraphReading(
                                          text: values[i].$1, unit: values[i].$2, name: items[i].name,
                                          color: items[i].color),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                      const SizedBox(width: 12),
                      DefaultTextStyle(
                        style: const TextStyle(color: Ns.muted, fontSize: 13, height: 18 / 13, fontFeatures: Ns.tabular),
                        textAlign: TextAlign.right,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // the high and low are one sensor's; with several, the values say it
                            if (single && layout != null) ...[
                              Text('↑ ${fmt(layout.hi, items.first.decimals)}'),
                              Text('↓ ${fmt(layout.lo, items.first.decimals)}'),
                            ],
                            Text(graphLabel(_hours)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
