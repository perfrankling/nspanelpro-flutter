import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/fill_card.dart';
import '../ui/sheet.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/icons.dart';
import 'actions.dart';
import 'echo.dart';
import 'env.dart';

// media_player supported_features
const _pause = 1,
    _volumeSet = 4,
    _volumeMute = 8,
    _prev = 16,
    _next = 32,
    _turnOff = 256,
    _stop = 4096,
    _play = 16384;

const _mutedGrey = Color(0xFF8E939B);

/// What the media card and its sheet both need, without a widget: the button
/// card's `long_press: sheet` opens the same sheet with no card behind it.
class MediaLogic {
  MediaLogic(this.env, this.c);
  final PanelEnv env;
  final CardConfig c;

  String get entity => c.str('entity') ?? '';
  int get echoMs => c.intOr('echo_ms', 1500);
  HaState? get state => env.states.get(entity);
  Color get accent => parseHex(c.str('accent')) ?? Ns.violet;
  List<CardConfig> get presets => c.maps('presets');

  Future<void> call(String service, [Map<String, dynamic>? data]) =>
      env.conn.callService('media_player', service, {'entity_id': entity, ...?data});

  bool idle(HaState? s) => s == null || const {'off', 'idle', 'standby'}.contains(s.state);
  bool playing(HaState? s) => s?.state == 'playing';
  bool muted(HaState? s) => s?.attributes['is_volume_muted'] == true;

  double entityValue(HaState? s) => (s?.numAttr('volume_level') ?? 0).clamp(0.0, 1.0);

  void commit(double v) {
    // Without VOLUME_SET there is nothing to commit to; the fill still moved.
    final s = state;
    if (s == null || !s.supports(_volumeSet)) return;
    call('volume_set', {'volume_level': (v * 100).round() / 100});
  }

  /// volume_zoom: below volume_zoom_below percent the card is a
  /// 0-volume_zoom slider, so the quiet end gets the whole card. 0 is off.
  /// Same rule as _fillSpan() in the web card.
  double span(double volume) {
    final zoom = c.numOr('volume_zoom', 0);
    if (zoom <= 0 || zoom >= 100) return 1;
    final pct = volume * 100;
    return pct < c.numOr('volume_zoom_below', 25) && pct <= zoom ? zoom / 100 : 1;
  }

  /// A favourite: volume_pct first, then a button-style action (entity /
  /// service / data), then the older shorthands, which still work - source
  /// selects a source on this player, media_content_id plays it here.
  /// Returns the volume to hold in the echo window, if it sets one.
  double? applyPreset(CardConfig p) {
    double? held;
    final vol = (p['volume_pct'] as num?)?.toDouble();
    if (vol != null) {
      held = (vol / 100).clamp(0.0, 1.0);
      call('volume_set', {'volume_level': held});
    }
    if (p['entity'] != null || p['service'] != null) fireItem(env, p);
    if (p['source'] != null) call('select_source', {'source': p['source']});
    if (p['media_content_id'] != null) {
      call('play_media', {
        'media_content_id': p['media_content_id'],
        'media_content_type': p['media_content_type'] ?? 'music',
      });
    }
    return held;
  }

  /// Tap: the tap_* action if there is one, else play/pause. tap_service
  /// without tap_entity sends exactly tap_data - the card adds no player.
  void tap() {
    if (c['tap_entity'] != null || c['tap_service'] != null) {
      fireAction(env, entity: c.str('tap_entity'), service: c.str('tap_service'), data: c['tap_data']);
      return;
    }
    call('media_play_pause');
  }

  ({String top, String sub}) lines(HaState? s) {
    final device = c.titleOr(friendlyName(s, entity));
    if (s == null || s.isBroken) return (top: device, sub: 'Unavailable');
    if (idle(s)) return (top: device, sub: s.state == 'off' ? 'Off' : 'Nothing playing');
    final title = s.attr<String>('media_title');
    final top = title ?? device;
    final sub = s.attr<String>('media_artist') ??
        s.attr<String>('media_series_title') ??
        s.attr<String>('media_channel') ??
        s.attr<String>('media_album_name') ??
        (title != null ? device : (s.state == 'paused' ? 'Paused' : 'Playing'));
    return (top: top, sub: s.state == 'paused' ? 'Paused · $sub' : sub);
  }

  /// The sheet, as of now: the next track, play turning to pause, a volume
  /// set elsewhere all show while it is open. A tap on the track mutes and
  /// unmutes where the player can; the sheet is always 0-100.
  SheetSpec sheet(EchoBox echo, VoidCallback changed) {
    final s = state;
    final l = lines(s);
    void hold(double v) {
      echo.hold(v, echoMs);
      changed();
    }

    return SheetSpec(
      title: l.top,
      state: l.sub,
      value: echo.display(entityValue(s)),
      accent: accent,
      step: c.numOr('step', 5),
      muted: muted(s),
      onTap: (s?.supports(_volumeMute) ?? false)
          ? () => call('volume_mute', {'is_volume_muted': !muted(state)})
          : null,
      actions: [
        if (s?.supports(_prev) ?? false)
          SheetAction(label: 'Previous', icon: MdiIcons.skipPrevious, close: false, run: () => call('media_previous_track')),
        SheetAction(
          label: playing(s) ? 'Pause' : 'Play',
          icon: playing(s) ? MdiIcons.pause : MdiIcons.play,
          primary: true,
          close: false,
          run: () => call('media_play_pause'),
        ),
        if (s?.supports(_next) ?? false)
          SheetAction(label: 'Next', icon: MdiIcons.skipNext, close: false, run: () => call('media_next_track')),
        if (s?.supports(_stop) ?? false)
          SheetAction(label: 'Stop', icon: MdiIcons.stop, run: () => call('media_stop'))
        else if (s?.supports(_turnOff) ?? false)
          SheetAction(label: 'Off', icon: MdiIcons.power, run: () => call('turn_off')),
      ],
      onInput: hold,
      onCommit: (v) {
        hold(v);
        commit(v);
      },
    );
  }
}

/// Volume on the drag, transport on the face. Album art is a fixed box (76px,
/// 52px beside the text when the card runs sideways) and Flutter's image cache
/// is keyed by URL, so an unchanged picture is never decoded twice - the guard
/// the web card has to keep by hand.
class MediaCard extends StatefulWidget {
  const MediaCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> with EchoMixin {
  CardConfig get c => widget.config;
  MediaLogic get l => MediaLogic(widget.env, c);
  String get entity => l.entity;

  /// volume_zoom's scale, pinned for as long as a finger is down so it never
  /// changes under it; worked out again on release.
  double? _spanLock;

  IconData _defaultIcon(HaState? s) {
    switch (s?.deviceClass) {
      case 'tv':
        return MdiIcons.television;
      case 'receiver':
        return MdiIcons.speaker;
      default:
        return MdiIcons.music;
    }
  }

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
        final idle = logic.idle(s);
        final v = display(logic.entityValue(s));
        final pct = (v * 100).round();
        final span = _spanLock ?? logic.span(v);
        final lines = logic.lines(s);
        final height = c.numOr('height', 200);
        final horizontal = c.str('fill_direction') == 'horizontal';
        final art = c.boolOr('show_art', true) && !broken ? s.attr<String>('entity_picture') : null;
        final playing = logic.playing(s);
        final muted = logic.muted(s);
        final artSize = horizontal ? 52.0 : 76.0;

        Widget leading;
        if (art != null) {
          leading = ClipRRect(
            borderRadius: BorderRadius.circular(horizontal ? 12 : 14),
            child: Image.network(
              widget.env.settings.resolve(art),
              width: artSize,
              height: artSize,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => IconBox(_defaultIcon(s), on: !idle),
            ),
          );
        } else {
          final name = c.str('icon') ?? s?.attr<String>('icon');
          leading = IconBox(mdi(name, _defaultIcon(s)), name: name, on: !idle && !broken);
        }

        // Button rows a horizontal card has no room for are left out,
        // transport first, favourites if there is still room.
        var rows = chipRowsThatFit(height, horizontal: horizontal);
        final showTransport = c.boolOr('show_transport', true) && rows > 0;
        if (showTransport) rows--;
        final showFavourites = c.boolOr('show_presets', true) && logic.presets.isNotEmpty && rows > 0;

        return FillCard(
          height: height,
          accent: logic.accent,
          horizontal: horizontal,
          solid: c.str('fill_style') == 'solid',
          fill: broken ? 0 : (v / span).clamp(0.0, 1.0),
          fillOpacity: broken || idle ? 0 : 1,
          on: !idle && !broken,
          broken: broken,
          opaqueChips: true,
          leading: leading,
          value: broken || idle || s.numAttr('volume_level') == null
              ? null
              : ValueText(
                  '$pct',
                  unit: '%',
                  // a muted player keeps its volume on show, in grey
                  color: muted ? _mutedGrey : Ns.text,
                  caption: span < 1 ? '0–${(span * 100).round()}' : null,
                ),
          title: lines.top,
          sub: lines.sub,
          chips: showTransport
              ? [
                  ChipSpec(
                      label: '',
                      icon: MdiIcons.skipPrevious,
                      disabled: broken || !s.supports(_prev),
                      onTap: () => logic.call('media_previous_track')),
                  ChipSpec(
                      label: '',
                      icon: playing ? MdiIcons.pause : MdiIcons.play,
                      disabled: broken || !(s.supports(_play) || s.supports(_pause)),
                      onTap: () => logic.call('media_play_pause')),
                  ChipSpec(
                      label: '',
                      icon: MdiIcons.skipNext,
                      disabled: broken || !s.supports(_next),
                      onTap: () => logic.call('media_next_track')),
                ]
              : const [],
          chips2: showFavourites
              ? [
                  for (final p in logic.presets.take(4))
                    ChipSpec(
                      label: p.str('name') ?? '',
                      onTap: () {
                        final held = logic.applyPreset(p);
                        if (held != null) holdLocal(held, logic.echoMs);
                      },
                    ),
                ]
              : const [],
          onTap: logic.tap,
          onLongPress: c.str('long_press') == 'none' ? null : _openSheet,
          // the drag works in fill fractions; the volume is that times the scale
          onDragValue: (nf) {
            _spanLock ??= span;
            dragging = true;
            setLocal(nf * _spanLock!);
          },
          onDragEnd: (nf) {
            final nv = nf * (_spanLock ?? span);
            _spanLock = null;
            dragging = false;
            holdLocal(nv, logic.echoMs);
            logic.commit(nv);
          },
        );
      },
    );
  }
}
