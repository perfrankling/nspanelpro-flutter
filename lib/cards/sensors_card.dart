import 'dart:async';

import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/graph.dart';
import '../ui/info_shell.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import 'env.dart';

/// Two to four readings side by side. The density card. Each reading is its
/// icon with the number and name beside it, no box around it; numbers are the
/// control cards' 40px. Three or four with icons do not fit a Pro 86 across,
/// and show_icons: false is the answer to that - an overlong number ends in
/// an ellipsis inside its own reading rather than running into the next.
class SensorsCard extends StatelessWidget {
  const SensorsCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  /// "sensor.x", {entity, name, icon, unit, decimals}, or {clock: true, name,
  /// icon, hour_24, show_seconds}: the panel's own time, as the clock card
  /// shows it, instead of a sensor.time that moves when HA sends it.
  List<CardConfig> get items => config
      .maps('entities')
      .where((i) => i['entity'] != null || i['clock'] == true)
      .take(4)
      .toList();

  @override
  Widget build(BuildContext context) {
    final ids = [for (final i in items) if (i['clock'] != true) i.str('entity')].whereType<String>().toList();
    final showIcons = config.boolOr('show_icons', true);
    return AnimatedBuilder(
      animation: Listenable.merge([for (final id in ids) env.states.listen(id)]),
      builder: (context, _) => InfoShell(
        height: config.numOr('height', 130),
        accent: parseHex(config.str('accent')) ?? Ns.sky,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(child: _cell(context, items[i], showIcons)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, CardConfig item, bool showIcons) {
    if (item['clock'] == true) return _LocalTime(item: item, showIcons: showIcons);
    final id = item.str('entity') ?? '';
    // a reading's last hours, full-screen: on a long-press, and on a tap - the
    // app's stand-in for the more-info dialog a tap opens in the browser
    void graph() => showGraphView(context, env: env, items: [
          GraphItem(
            entity: id,
            name: item.str('name') ?? friendlyName(env.states.get(id), id),
            color: parseHex(config.str('accent')) ?? Ns.sky,
            unit: item.str('unit'),
            decimals: item['decimals'] as int?,
          ),
        ]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: config.boolOr('more_info', true) ? graph : null,
      onLongPress: config.str('long_press') == 'none' ? null : graph,
      child: _reading(item, id, showIcons),
    );
  }

  Widget _reading(CardConfig item, String id, bool showIcons) {
    final s = env.states.get(id);
    final broken = s == null || s.isBroken;
    final n = s?.numeric;
    final unit = item['unit'] != null ? item.str('unit')! : (s?.unit ?? '');
    final text = broken ? '—' : (n == null ? s.state : fmt(n, item['decimals'] as int?));
    return Row(
      children: [
        if (showIcons) ...[
          iconWidget(item.str('icon') ?? s?.attr<String>('icon') ?? classIcon(s, id), size: 28, color: Ns.muted),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BigValue(text, unit: broken ? '' : unit, size: 40),
              const SizedBox(height: 4),
              Text(item.str('name') ?? friendlyName(s, id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Ns.muted, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A reading that is the time on this panel's clock. Its own timer, re-armed
/// against the wall clock each tick as the clock card's is - every minute, or
/// every second with show_seconds - so a tick rebuilds this reading alone and
/// never the sensors beside it. No entity, so a tap does nothing.
class _LocalTime extends StatefulWidget {
  const _LocalTime({required this.item, required this.showIcons});
  final CardConfig item;
  final bool showIcons;

  @override
  State<_LocalTime> createState() => _LocalTimeState();
}

class _LocalTimeState extends State<_LocalTime> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  CardConfig get item => widget.item;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_LocalTime old) {
    super.didUpdateWidget(old);
    // show_seconds may have changed: the next tick at the new period
    _timer?.cancel();
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _arm() {
    _now = DateTime.now();
    final period = item['show_seconds'] == true ? 1000 : 60000;
    final wait = period - (_now.millisecondsSinceEpoch % period) + 20;
    _timer = Timer(Duration(milliseconds: wait), () {
      if (!mounted) return;
      setState(_arm);
    });
  }

  @override
  Widget build(BuildContext context) {
    final h24 = item['hour_24'] != false;
    var h = _now.hour;
    var suffix = '';
    if (!h24) {
      suffix = h < 12 ? 'am' : 'pm';
      h = h % 12 == 0 ? 12 : h % 12;
    }
    final hh = h24 ? h.toString().padLeft(2, '0') : h.toString();
    final mm = _now.minute.toString().padLeft(2, '0');
    final ss = item['show_seconds'] == true ? ':${_now.second.toString().padLeft(2, '0')}' : '';
    return Row(
      children: [
        if (widget.showIcons) ...[
          iconWidget(item.str('icon') ?? 'mdi:clock-outline', size: 28, color: Ns.muted),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BigValue('$hh:$mm$ss', unit: suffix, size: 40),
              const SizedBox(height: 4),
              // a name of '' is an empty label, not the default
              Text(item['name'] != null ? '${item['name']}' : 'Time',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Ns.muted, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
