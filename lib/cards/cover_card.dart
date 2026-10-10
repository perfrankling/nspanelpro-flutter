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

// cover supported_features
const _setPosition = 4, _openTilt = 16, _closeTilt = 32, _setTilt = 128;

/// What the cover card and its sheet both need, without a widget: the button
/// card's `long_press: sheet` opens the same sheet with no card behind it.
class CoverLogic {
  CoverLogic(this.env, this.c);
  final PanelEnv env;
  final CardConfig c;

  String get entity => c.str('entity') ?? '';
  int get echoMs => c.intOr('echo_ms', 1500);
  HaState? get state => env.states.get(entity);
  Color get accent => parseHex(c.str('accent')) ?? Ns.sky;

  List<CardConfig> get presets => c['presets'] is List
      ? c.maps('presets')
      : const [
          {'name': 'Open', 'position': 100},
          {'name': 'Half', 'position': 50},
          {'name': 'Shut', 'position': 0},
        ];

  /// value = how OPEN it is, 0..1
  double entityValue(HaState? s) {
    if (s == null) return 0;
    final p = s.numAttr('current_position');
    if (p != null) return (p / 100).clamp(0.0, 1.0);
    return s.state == 'open' ? 1 : 0;
  }

  double tiltValue(HaState? s) => ((s?.numAttr('current_tilt_position') ?? 0) / 100).clamp(0.0, 1.0);

  bool moving(HaState? s) => s != null && (s.state == 'opening' || s.state == 'closing');

  Future<void> call(String service, [Map<String, dynamic>? data]) =>
      env.conn.callService('cover', service, {'entity_id': entity, ...?data});

  void commit(double v) {
    final pct = (v * 100).round();
    final s = state;
    if (s != null && s.supports(_setPosition)) {
      call('set_cover_position', {'position': pct});
    } else {
      call(pct > 50 ? 'open_cover' : 'close_cover');
    }
  }

  String stateText(HaState? s, int pct) {
    if (s == null) return '';
    if (s.state == 'opening') return 'Opening';
    if (s.state == 'closing') return 'Closing';
    if (s.numAttr('current_position') != null) {
      return pct >= 99 ? 'Open' : (pct <= 0 ? 'Closed' : '$pct% open');
    }
    return s.state == 'open' ? 'Open' : 'Closed';
  }

  /// The sheet, as of now. A cover that can set its tilt gets a second track,
  /// Position and Tilt side by side, both filling down from the top; one that
  /// can open and close its tilt gets HA's tilt buttons in place of the ± steps.
  SheetSpec sheet(EchoBox echo, EchoBox tiltEcho, VoidCallback changed) {
    final s = state;
    final v = echo.display(entityValue(s));
    void hold(double nv) {
      echo.hold(nv, echoMs);
      changed();
    }

    final tiltButtons = (s?.supports(_openTilt) ?? false) && (s?.supports(_closeTilt) ?? false);
    return SheetSpec(
      title: c.titleOr(friendlyName(s, entity)),
      state: stateText(s, (v * 100).round()),
      value: v,
      fromTop: true,
      accent: accent,
      step: c.numOr('step', 5),
      label: 'Position',
      tilt: (s?.supports(_setTilt) ?? false)
          ? SheetTrack(
              label: 'Tilt',
              value: tiltEcho.display(tiltValue(s)),
              fromTop: true,
              onInput: (t) => tiltEcho.hold(t, echoMs),
              onCommit: (t) {
                tiltEcho.hold(t, echoMs);
                call('set_cover_tilt_position', {'tilt_position': (t * 100).round()});
              },
            )
          : null,
      stepUp: tiltButtons
          ? SheetAction(label: 'Tilt open', icon: MdiIcons.rotateLeft, run: () => call('open_cover_tilt'))
          : null,
      stepDown: tiltButtons
          ? SheetAction(label: 'Tilt close', icon: MdiIcons.rotateRight, run: () => call('close_cover_tilt'))
          : null,
      actions: [
        SheetAction(label: 'Open', icon: MdiIcons.arrowUp, run: () => call('open_cover')),
        SheetAction(label: 'Stop', icon: MdiIcons.stop, primary: true, close: false, run: () => call('stop_cover')),
        SheetAction(label: 'Close', icon: MdiIcons.arrowDown, run: () => call('close_cover')),
      ],
      onInput: hold,
      onCommit: (nv) {
        hold(nv);
        commit(nv);
      },
    );
  }
}

class CoverCard extends StatefulWidget {
  const CoverCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<CoverCard> createState() => _CoverCardState();
}

class _CoverCardState extends State<CoverCard> with EchoMixin {
  CardConfig get c => widget.config;
  CoverLogic get l => CoverLogic(widget.env, c);
  String get entity => l.entity;
  final _tiltEcho = EchoBox();

  void _openSheet() => showControlSheet(
        context,
        spec: () => l.sheet(echo, _tiltEcho, echoChanged),
        listen: widget.env.states.listen(entity),
      );

  @override
  Widget build(BuildContext context) {
    final logic = l;
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entity),
      builder: (context, s, _) {
        final broken = s == null || s.isBroken;
        final v = display(logic.entityValue(s));
        final pct = (v * 100).round();
        final height = c.numOr('height', 200);
        final horizontal = c.str('fill_direction') == 'horizontal';
        final showPresets = c.boolOr('show_presets', true) &&
            logic.presets.isNotEmpty &&
            chipRowsThatFit(height, horizontal: horizontal) > 0;
        final icon = c.str('icon') ??
            s?.attr<String>('icon') ??
            (pct >= 99 ? 'mdi:blinds-open' : (pct <= 0 ? 'mdi:blinds' : 'mdi:blinds-horizontal'));

        return FillCard(
          height: height,
          accent: logic.accent,
          // The fill descends from the top, the way a blind actually does.
          // Sideways it comes in from the left, and dragging right brings it
          // down: the drag runs against the value, which is how open it is.
          fill: broken ? 1 : v,
          fillOpacity: broken ? 0 : 1,
          fromTop: true,
          horizontal: horizontal,
          dragSign: horizontal ? -1 : 1,
          solid: c.str('fill_style') == 'solid',
          on: !broken && pct < 55,
          broken: broken,
          leading: IconBox(mdi(icon), name: icon, on: !broken && pct < 55),
          value: ValueText(broken ? '—' : '$pct', unit: broken ? '' : '%'),
          title: c.titleOr(friendlyName(s, entity)),
          sub: broken ? 'Unavailable' : logic.stateText(s, pct),
          chips: showPresets
              ? [
                  for (final p in logic.presets.take(4))
                    ChipSpec(
                      label: p.str('name') ?? '${p['position']}%',
                      onTap: () {
                        final pos = (p['position'] as num?)?.toDouble();
                        if (pos == null) return;
                        holdLocal(pos / 100, logic.echoMs);
                        logic.commit(pos / 100);
                      },
                    ),
                ]
              : const [],
          // a tap while it is moving stops it; otherwise it toggles
          onTap: () => logic.call(logic.moving(s) ? 'stop_cover' : 'toggle'),
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
