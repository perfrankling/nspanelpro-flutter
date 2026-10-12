import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/fill_card.dart';
import '../ui/sheet.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/icons.dart';
import 'echo.dart';
import 'env.dart';

/// What the light card and its sheet both need, without a widget: the button
/// card's `long_press: sheet` opens the same sheet with no card behind it.
class LightLogic {
  LightLogic(this.env, this.c);
  final PanelEnv env;
  final CardConfig c;

  String get entity => c.str('entity') ?? '';
  int get echoMs => c.intOr('echo_ms', 1500);
  HaState? get state => env.states.get(entity);

  List<CardConfig> get presets => c['presets'] is List
      ? c.maps('presets')
      : const [
          {'name': 'Low', 'brightness_pct': 15},
          {'name': 'Mid', 'brightness_pct': 50},
          {'name': 'Full', 'brightness_pct': 100},
        ];

  double entityValue(HaState? s) {
    if (s == null || !s.isOn) return 0;
    final b = s.numAttr('brightness');
    return b == null ? 1 : (b / 255).clamp(0.0, 1.0);
  }

  /// The colour to paint the card in: the bulb's own when it has one and is
  /// on, otherwise the configured accent. An explicit accent always wins.
  Color accent(HaState? s) {
    final explicit = parseHex(c.str('accent'));
    if (explicit != null) return explicit;
    if (c.boolOr('follow_color', true) && s != null && s.isOn) {
      final rgb = s.attributes['rgb_color'];
      if (rgb is List && rgb.length >= 3 && rgb.every((x) => x is num)) {
        return readableTint(rgb.cast<num>());
      }
    }
    return Ns.amber;
  }

  Future<void> call(String service, [Map<String, dynamic>? data]) =>
      env.conn.callService('light', service, {'entity_id': entity, ...?data});

  void commit(double v) {
    final pct = (v * 100).round();
    if (pct == 0) {
      call('turn_off');
    } else {
      call('turn_on', {'brightness_pct': pct});
    }
  }

  /// Returns the level to hold in the echo window, if the preset sets one.
  double? applyPreset(CardConfig p) {
    if (p['scene'] != null) {
      env.conn.callService('scene', 'turn_on', {'entity_id': p['scene']});
      return null;
    }
    final pct = (p['brightness_pct'] as num?)?.toInt();
    if (pct == 0) {
      call('turn_off');
      return 0;
    }
    final data = <String, dynamic>{};
    if (pct != null) data['brightness_pct'] = pct;
    for (final k in ['color_temp_kelvin', 'rgb_color', 'effect']) {
      if (p[k] != null) data[k] = p[k];
    }
    call('turn_on', data);
    return pct == null ? null : pct / 100;
  }

  /// The sheet, as of now: called again on every state change while it is open.
  SheetSpec sheet(EchoBox echo, VoidCallback changed) {
    final s = state;
    final on = s?.isOn ?? false;
    void hold(double v) {
      echo.hold(v, echoMs);
      changed();
    }

    return SheetSpec(
      title: c.titleOr(friendlyName(s, entity)),
      state: on ? 'On' : 'Off',
      value: echo.display(entityValue(s)),
      accent: accent(s),
      step: c.numOr('step', 5),
      actions: [
        for (final p in presets.take(3))
          SheetAction(
            label: p.str('name') ?? '${p['brightness_pct']}%',
            icon: mdi(p.str('icon'), MdiIcons.lightbulbOnOutline),
            run: () {
              final v = applyPreset(p);
              if (v != null) hold(v);
            },
          ),
        SheetAction(
          label: on ? 'Turn off' : 'Turn on',
          icon: on ? MdiIcons.lightbulbOff : MdiIcons.lightbulbOn,
          primary: true,
          run: () => call('toggle'),
        ),
      ],
      onInput: hold,
      onCommit: (v) {
        hold(v);
        commit(v);
      },
    );
  }
}

class LightCard extends StatefulWidget {
  const LightCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<LightCard> createState() => _LightCardState();
}

class _LightCardState extends State<LightCard> with EchoMixin {
  CardConfig get c => widget.config;
  LightLogic get l => LightLogic(widget.env, c);
  String get entity => l.entity;

  void _openSheet() => showControlSheet(
        context,
        spec: () => l.sheet(echo, echoChanged),
        listen: widget.env.states.listen(entity),
      );

  @override
  Widget build(BuildContext context) {
    final logic = l;
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entity),
      builder: (context, s, _) {
        final broken = s == null || s.isBroken;
        final on = s?.isOn ?? false;
        final v = display(logic.entityValue(s));
        final pct = (v * 100).round();
        final height = c.numOr('height', 200);
        final horizontal = c.str('fill_direction') == 'horizontal';
        // a horizontal card too low for the chips leaves them out
        final showPresets = c.boolOr('show_presets', true) &&
            logic.presets.isNotEmpty &&
            chipRowsThatFit(height, horizontal: horizontal) > 0;
        final iconName = c.str('icon') ?? s?.attr<String>('icon');

        return FillCard(
          height: height,
          accent: logic.accent(s),
          horizontal: horizontal,
          solid: c.str('fill_style') == 'solid',
          fill: on && !broken ? v : 0,
          fillOpacity: on && !broken ? 1 : 0,
          on: on && !broken,
          broken: broken,
          dragTravel: c['drag_travel'] is num && c.numOr('drag_travel', 0) > 0 ? c.numOr('drag_travel', 0) : null,
          leading: IconBox(
            mdi(iconName, on ? MdiIcons.lightbulbOn : MdiIcons.lightbulbOutline),
            name: iconName,
            on: on,
          ),
          // show_value: false leaves the big number and its plate out; the
          // state line under the name keeps the level
          value: on && c.boolOr('show_value', true) ? ValueText('$pct', unit: '%') : null,
          title: c.titleOr(friendlyName(s, entity)),
          sub: broken ? 'Unavailable' : (on ? 'On · $pct%' : 'Off'),
          chips: showPresets
              ? [
                  for (final p in logic.presets.take(4))
                    ChipSpec(
                      label: p.str('name') ?? '${p['brightness_pct']}%',
                      onTap: () {
                        final nv = logic.applyPreset(p);
                        if (nv != null) holdLocal(nv, logic.echoMs);
                      },
                    ),
                ]
              : const [],
          onTap: () => logic.call('toggle'),
          onLongPress: c.str('long_press') == 'none' ? null : _openSheet,
          onDragValue: (nv) {
            dragging = true;
            setLocal(nv);
          },
          onDragEnd: (nv) {
            dragging = false;
            holdLocal(nv, logic.echoMs);
            logic.commit(nv);
          },
        );
      },
    );
  }
}
