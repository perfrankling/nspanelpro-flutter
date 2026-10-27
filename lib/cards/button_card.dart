import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/info_shell.dart';
import '../ui/sheet.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/icons.dart';
import 'actions.dart';
import 'cover_card.dart';
import 'echo.dart';
import 'env.dart';
import 'light_card.dart';
import 'media_card.dart';

const _domainIcons = {
  'script': 'mdi:script-text-outline',
  'scene': 'mdi:palette-outline',
  'automation': 'mdi:robot-outline',
};

/// Scenes, scripts, automations. A script has no state to reflect, so the
/// button supplies the acknowledgement itself: a haptic, and a tick held for
/// feedback_ms. `confirm` asks for a second tap, because a wall panel is
/// exactly the thing people brush past.
class ButtonCard extends StatefulWidget {
  const ButtonCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<ButtonCard> createState() => _ButtonCardState();
}

class _Btn {
  _Btn(this.item);
  final CardConfig item;
  bool armed = false;
  bool fired = false;
}

class _ButtonCardState extends State<ButtonCard> {
  CardConfig get c => widget.config;
  late final List<_Btn> _btns = _items().map(_Btn.new).toList();
  final _timers = <Timer>[];

  /// The echo windows of the sheets a long-press opens, one per entity.
  final _echoes = <String, (EchoBox, EchoBox)>{};

  List<CardConfig> _items() {
    final list = c['buttons'] is List && c.listOr('buttons').isNotEmpty
        ? c.maps('buttons')
        : (c['entity'] != null
              ? [
                  {
                    'entity': c['entity'],
                    'name': c.str('title') ?? c.str('name'),
                    'icon': c['icon'],
                  },
                ]
              : <CardConfig>[]);
    return list
        .where((i) => i['entity'] != null || i['service'] != null)
        .take(6)
        .toList();
  }

  /// What lights the button: `state_entity` when given, else the button's
  /// own entity - a running script, a switch or boolean that is on.
  bool _lit(CardConfig item) {
    final id = item.str('state_entity') ?? item.str('entity');
    return id != null && widget.env.states.get(id)?.state == 'on';
  }

  bool _showName(CardConfig item) => item['show_name'] is bool
      ? item['show_name'] as bool
      : c.boolOr('show_name', true);

  double _iconScale(CardConfig item) =>
      (item['icon_scale'] as num?)?.toDouble() ?? c.numOr('icon_scale', 1);

  /// 1 to 4 across, and never more columns than buttons: the row is always
  /// shared by the buttons in it, and the compact styling belongs to three
  /// and four across.
  int get _columns {
    if (_btns.isEmpty) return 1;
    return c.intOr('columns', 2).clamp(1, 4).clamp(1, _btns.length);
  }

  /// color_attribute: the button's colour, read from an attribute of
  /// color_entity (default: the button's own entity). Black, none or empty
  /// mean "not painted" - a black button on this card reads as a hole.
  /// `colors` maps names to the owner's palette, case-insensitively; a name it
  /// does not list is used as it is. Text goes dark on a light colour.
  ({Color bg, Color fg})? _paint(CardConfig item) {
    final attr = item.str('color_attribute');
    if (attr == null) return null;
    final id = item.str('color_entity') ?? item.str('entity');
    final raw = id == null ? null : widget.env.states.get(id)?.attributes[attr];
    final name = raw == null ? '' : '$raw'.trim();
    final low = name.toLowerCase();
    if (name.isEmpty || low == 'black' || low == 'none') return null;
    final map = c['colors'] is Map ? (c['colors'] as Map) : const {};
    Object? mapped;
    for (final e in map.entries) {
      if ('${e.key}'.toLowerCase() == low) mapped = e.value;
    }
    final bg = parseColour(mapped != null ? '$mapped' : name);
    if (bg == null) return null;
    return (bg: bg, fg: luminance255(bg) > 150 ? const Color(0xFF14161A) : Colors.white);
  }

  /// long_press, per button or for the card. The app has no HA dialog to
  /// open, so `more-info` - and the old default, `more_info` - open the same
  /// full-screen control as `sheet` for a light, cover or media player, and
  /// do nothing for anything else.
  String _longPressFor(CardConfig item) {
    if (item.str('entity') == null) return 'none';
    final lp = item.str('long_press') ?? c.str('long_press');
    if (lp != null) return lp;
    return c.boolOr('more_info', true) ? 'more-info' : 'none';
  }

  void _longPress(CardConfig item) {
    if (_longPressFor(item) == 'none') return;
    final entity = item.str('entity')!;
    final env = widget.env;
    final cfg = <String, dynamic>{'entity': entity, if (c['accent'] != null) 'accent': c['accent']};
    final (echo, tilt) = _echoes.putIfAbsent(entity, () => (EchoBox(), EchoBox()));
    void changed() {}
    SheetSpec Function()? spec;
    switch (entity.split('.').first) {
      case 'light':
        spec = () => LightLogic(env, cfg).sheet(echo, changed);
      case 'cover':
        spec = () => CoverLogic(env, cfg).sheet(echo, tilt, changed);
      case 'media_player':
        spec = () => MediaLogic(env, cfg).sheet(echo, changed);
    }
    if (spec == null) return;
    if (c.boolOr('haptics', true)) HapticFeedback.mediumImpact();
    showControlSheet(context, spec: spec, listen: env.states.listen(entity));
  }

  void _later(VoidCallback fn, int ms) =>
      _timers.add(Timer(Duration(milliseconds: ms), fn));

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _press(_Btn b) {
    if (c.boolOr('haptics', true)) HapticFeedback.lightImpact();
    final wantsConfirm = b.item['confirm'] is bool
        ? b.item['confirm'] as bool
        : c.boolOr('confirm', false);
    if (wantsConfirm && !b.armed) {
      setState(() => b.armed = true);
      _later(() {
        if (mounted) setState(() => b.armed = false);
      }, 3000);
      return;
    }
    b.armed = false;
    fireItem(widget.env, b.item);
    setState(() => b.fired = true);
    _later(() {
      if (mounted) setState(() => b.fired = false);
    }, c.intOr('feedback_ms', 1200));
  }

  @override
  Widget build(BuildContext context) {
    final ids = [
      for (final b in _btns) ...[
        b.item.str('entity'),
        b.item.str('state_entity'),
        b.item.str('color_entity'),
      ],
    ].whereType<String>().toList();
    final accent = parseHex(c.str('accent')) ?? Ns.mint;
    return AnimatedBuilder(
      animation: Listenable.merge([
        for (final id in ids) widget.env.states.listen(id),
      ]),
      builder: (context, _) => InfoShell(
        height: c.numOr('height', 200),
        accent: accent,
        padding: const EdgeInsets.all(12),
        child: TileGrid(
          columns: _columns,
          stretch: true,
          children: [for (final b in _btns) _tile(b, accent)],
        ),
      ),
    );
  }

  Widget _tile(_Btn b, Color cardAccent) {
    final entity = b.item.str('entity');
    final s = entity == null ? null : widget.env.states.get(entity);
    // Not isBroken(): `unknown` is the normal resting state of a scene that has
    // never been fired. Only a missing or unavailable entity is a dead button.
    final broken = entity != null && (s == null || s.state == 'unavailable');
    final hot = b.fired || _lit(b.item);
    final cols = _columns;
    // a colour of its own: the lit state uses it instead of the card's accent
    final accent = parseHex(b.item.str('color')) ?? cardAccent;
    final showName = _showName(b.item);
    // painted from an attribute: that is the state, and it wins over lit
    final paint = broken ? null : _paint(b.item);
    final scale = _iconScale(b.item);

    final label = b.armed
        ? (b.item.str('confirm_text') ?? c.str('confirm_text') ?? 'Tap again')
        : (b.item.str('name') ??
              (entity != null ? friendlyName(s, entity) : 'Run'));
    final iconName = broken
        ? 'mdi:alert-circle-outline'
        : b.fired
        ? 'mdi:check'
        : (b.item.str('icon') ??
              s?.attr<String>('icon') ??
              _domainIcons[entity?.split('.').first]);
    // white, lit or not: a lit button shows in its background and its name.
    // Painted from an attribute it takes the colour's own readable text colour.
    final iconColor = paint?.fg ?? Ns.text;
    final withName = showName || b.armed;

    // The long-press is timed here, at long_press_ms, so it can be set and so
    // it is the same with a finger or a mouse; it never also fires the button.
    final lp = _longPressFor(b.item) == 'none' || broken ? null : c.intOr('long_press_ms', 500);

    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          TapGestureRecognizer.new,
          (t) => t.onTap = broken ? null : () => _press(b),
        ),
        if (lp != null)
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: Duration(milliseconds: lp)),
            (r) => r.onLongPress = () => _longPress(b.item),
          ),
      },
      child: Opacity(
        opacity: broken ? .45 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: paint?.bg ?? (hot ? accent.withValues(alpha: .16) : Ns.surface2),
            borderRadius: CardRadius.inner(context, 18),
          ),
          padding: EdgeInsets.all(cols == 4 ? 6 : 8),
          child: LayoutBuilder(
            builder: (context, box) {
              // icon only: 60% of the button's shorter side, so a tall button
              // gets a big icon; with a name, the fixed size for the column count
              final size = withName
                  ? (cols >= 4 ? 28.0 : cols == 3 ? 32.0 : 40.0) * scale
                  : box.biggest.shortestSide * .6 * scale;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconWidget(iconName, fallback: MdiIcons.gestureTapButton, size: size, color: iconColor),
                  // icon only, unless it is waiting for the second tap: that has
                  // to be said, so the name's line comes back with "Tap again"
                  if (withName) SizedBox(height: cols == 4 ? 6 : 8),
                  if (withName)
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: paint?.fg ?? (hot || b.armed ? accent : Ns.text),
                        fontSize: cols >= 4 ? 13 : cols == 3 ? 15 : 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.2,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
