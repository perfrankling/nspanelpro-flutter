import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/fill_card.dart';
import '../ui/graph.dart';
import '../ui/info_shell.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import 'env.dart';

/// One reading, as large as the card allows. Optional range bar and severity.
class SensorCard extends StatelessWidget {
  const SensorCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  String get entity => config.str('entity') ?? '';
  String? get secondary => config.str('secondary');

  bool get _hasBar => config.boolOr('bar', true) && config['min'] is num && config['max'] is num;

  /// severity: [{above, color}] - last match wins, so the list reads in the
  /// order a person would say it.
  Color? _severity(num? n) {
    if (n == null || config['severity'] is! List) return null;
    Color? hit;
    for (final s in config.maps('severity')) {
      final above = s['above'];
      if (above is num && n > above) hit = parseHex(s.str('color') ?? s.str('colour')) ?? hit;
    }
    return hit;
  }

  @override
  Widget build(BuildContext context) {
    final ids = [entity, ?secondary];
    return AnimatedBuilder(
      animation: Listenable.merge([for (final id in ids) env.states.listen(id)]),
      builder: (context, _) {
        final s = env.states.get(entity);
        final broken = s == null || s.isBroken;
        final n = s?.numeric;
        final accent = _severity(n) ?? parseHex(config.str('accent')) ?? Ns.sky;
        final unit = config['unit'] != null ? config.str('unit')! : (s?.unit ?? '');
        final text = broken ? '—' : (n == null ? s.state : fmt(n, config['decimals'] as int?));

        double? fill;
        if (_hasBar && !broken && n != null) {
          final min = config.numOr('min', 0), max = config.numOr('max', 100);
          fill = ((n - min) / (max - min)).clamp(0.0, 1.0);
        }

        final iconName = config.str('icon') ?? s?.attr<String>('icon') ?? classIcon(s, entity);
        final sec = secondary == null ? null : env.states.get(secondary!);
        final sub = broken
            ? 'Unavailable'
            : (sec != null ? '${friendlyName(sec, secondary!)} ${fmt(sec.numeric)}${sec.unit}' : '');

        // this sensor's last hours, full-screen: on a long-press, and on a tap,
        // which in the browser opens HA's more-info - a dialog the app does
        // not have, whose main content is the same history
        void graph() => showGraphView(context, env: env, items: [
              GraphItem(
                entity: entity,
                name: config.titleOr(friendlyName(s, entity)),
                color: parseHex(config.str('accent')) ?? Ns.sky,
                unit: config.str('unit'),
                decimals: config['decimals'] as int?,
              ),
            ]);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: config.boolOr('more_info', true) ? graph : null,
          onLongPress: config.str('long_press') == 'none' ? null : graph,
          child: InfoShell(
            height: config.numOr('height', 200),
            accent: accent,
            fill: fill,
            broken: broken,
            // the icon, and the number, name and second line beside it, centred
            // in the height - the way the sideways control cards read
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  IconBox(mdi(iconName), name: iconName),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BigValue(text, unit: broken ? '' : unit),
                        Text(config.titleOr(friendlyName(s, entity)),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                        if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
