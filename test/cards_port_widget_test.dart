import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:nspanel_app/cards/button_card.dart';
import 'package:nspanel_app/cards/clock_card.dart';
import 'package:nspanel_app/cards/cover_card.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/light_card.dart';
import 'package:nspanel_app/cards/media_card.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/fill_card.dart';
import 'package:nspanel_app/util/color.dart';
import 'package:nspanel_app/util/custom_icons.dart';

import 'connection_test.dart' show FakeHa, st;

/// The card options that came over from the cards repo, 0.12 to 0.19:
/// fill_direction / fill_style, volume_zoom, the media card's actions, the live
/// sheet with mute and tilt, and the button card's columns, colours, icons and
/// long-press.

Future<(FakeHa, PanelEnv, HaConnection)> _house(Map<String, Map<String, dynamic>> s) async {
  final fake = FakeHa(s);
  final states = HaStates();
  final conn = HaConnection(transportFactory: () async => fake, token: 'good', states: states);
  final ready = Completer<void>();
  conn.onReady = ready.complete;
  await conn.start();
  await ready.future.timeout(const Duration(seconds: 2));
  return (fake, PanelEnv(states: states, conn: conn, settings: Settings(url: 'http://x', token: 't')), conn);
}

Widget _app(Widget card) => MaterialApp(home: Scaffold(body: Center(child: card)));

/// The number in the last call to [service], e.g. position or volume_level.
num _last(FakeHa fake, String service, String key) {
  final call = fake.calls.lastWhere((c) => c.startsWith('$service '));
  return num.parse(RegExp('"$key":([0-9.]+)').firstMatch(call)!.group(1)!);
}

void main() {
  testWidgets('light, sideways: a sideways drag sets it, a vertical one does not; low cards drop presets',
      (tester) async {
    final (fake, env, conn) = await _house({
      'light.desk': st('light.desk', 'on', {'friendly_name': 'Desk', 'brightness': 128}),
    });
    await tester.pumpWidget(_app(LightCard(
      config: {'entity': 'light.desk', 'height': 200, 'fill_direction': 'horizontal', 'show_presets': false},
      env: env,
    )));
    await tester.pump();

    await tester.drag(find.byType(LightCard), const Offset(200, 0));
    await tester.pump(const Duration(milliseconds: 50));
    // 50% plus 200px of an 800px card, less the touch slop before the drag is a drag
    expect(_last(fake, 'light.turn_on', 'brightness_pct'), inInclusiveRange(72, 75));

    final before = fake.calls.length;
    await tester.drag(find.byType(LightCard), const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.calls.length, before, reason: 'the vertical drag belongs to the page, not the light: ${fake.calls}');

    await tester.pumpWidget(_app(LightCard(
      config: {'entity': 'light.desk', 'height': 120, 'fill_direction': 'horizontal'},
      env: env,
    )));
    await tester.pump();
    expect(find.text('Low'), findsNothing, reason: 'presets need a 160px card sideways');
    unawaited(conn.dispose());
  });

  testWidgets('cover, sideways: dragging right brings it down', (tester) async {
    final (fake, env, conn) = await _house({
      'cover.blind': st('cover.blind', 'open', {'friendly_name': 'Blind', 'current_position': 62, 'supported_features': 15}),
    });
    await tester.pumpWidget(_app(CoverCard(
      config: {'entity': 'cover.blind', 'height': 200, 'fill_direction': 'horizontal', 'show_presets': false},
      env: env,
    )));
    await tester.pump();
    await tester.drag(find.byType(CoverCard), const Offset(200, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_last(fake, 'cover.set_cover_position', 'position'), inInclusiveRange(37, 40));
    unawaited(conn.dispose());
  });

  testWidgets('media, volume_zoom: quiet is drawn on 0-30, the scale holds for the drag', (tester) async {
    final (fake, env, conn) = await _house({
      'media_player.k': st('media_player.k', 'playing',
          {'friendly_name': 'Kitchen', 'volume_level': 0.18, 'supported_features': 4 | 8 | 1 | 16384}),
    });
    await tester.pumpWidget(_app(MediaCard(
      config: {'entity': 'media_player.k', 'height': 200, 'volume_zoom': 30, 'show_transport': false},
      env: env,
    )));
    await tester.pump();
    expect(find.text('0–30'), findsOneWidget);

    // all the way up: the card's whole height is 30%, and no further on this drag
    await tester.drag(find.byType(MediaCard), const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_last(fake, 'media_player.volume_set', 'volume_level'), 0.3);
    // released at 30: the next drag is on 0-100
    expect(find.text('0–30'), findsNothing);
    unawaited(conn.dispose());
  });

  testWidgets('media: tap and favourites take button-style actions; volume first', (tester) async {
    final (fake, env, conn) = await _house({
      'media_player.k': st('media_player.k', 'playing',
          {'friendly_name': 'Kitchen', 'volume_level': 0.4, 'supported_features': 4 | 1 | 16384}),
    });
    await tester.pumpWidget(_app(MediaCard(
      config: {
        'entity': 'media_player.k',
        'height': 300,
        'show_transport': false,
        'tap_service': 'script.sonos_onoff',
        'presets': [
          {'name': 'News', 'entity': 'script.news', 'volume_pct': 20},
          {'name': 'Radio', 'source': 'BBC Radio 4'},
        ],
      },
      env: env,
    )));
    await tester.pump();

    await tester.tapAt(tester.getTopLeft(find.byType(MediaCard)) + const Offset(200, 20));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.calls.last, 'script.sonos_onoff {}', reason: 'tap_service sends exactly tap_data');

    fake.calls.clear();
    await tester.tap(find.text('News'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.calls, [
      'media_player.volume_set {"entity_id":"media_player.k","volume_level":0.2}',
      'script.turn_on {"entity_id":"script.news"}',
    ]);

    fake.calls.clear();
    await tester.tap(find.text('Radio'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.calls, ['media_player.select_source {"entity_id":"media_player.k","source":"BBC Radio 4"}']);
    unawaited(conn.dispose());
  });

  testWidgets('media sheet: live while open, a tap on the track mutes, muted is grey', (tester) async {
    final (fake, env, conn) = await _house({
      'media_player.k': st('media_player.k', 'playing', {
        'friendly_name': 'Kitchen',
        'volume_level': 0.34,
        'media_title': 'First Song',
        'supported_features': 4 | 8 | 1 | 16 | 32 | 16384,
      }),
    });
    await tester.pumpWidget(_app(MediaCard(config: {'entity': 'media_player.k', 'height': 300}, env: env)));
    await tester.pump();
    await tester.longPress(find.byType(MediaCard));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('First Song'), findsWidgets);
    expect(find.text('Pause'), findsOneWidget);

    final attrs = fake.states['media_player.k']!['attributes'] as Map;
    attrs['media_title'] = 'Next Song';
    fake.states['media_player.k']!['state'] = 'paused';
    fake.push('media_player.k');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Next Song'), findsWidgets, reason: 'the sheet follows the player');
    expect(find.text('Play'), findsOneWidget);

    fake.calls.clear();
    await tester.tap(find.byKey(const ValueKey('main-track')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.calls, ['media_player.volume_mute {"entity_id":"media_player.k","is_volume_muted":true}']);
    final inTrack = find.descendant(of: find.byKey(const ValueKey('main-track')), matching: find.text('34%'));
    expect(inTrack, findsOneWidget, reason: 'a tap mutes; it does not move the volume');

    attrs['is_volume_muted'] = true;
    fake.push('media_player.k');
    await tester.pump(const Duration(milliseconds: 50));
    final pct = tester.widget<Text>(inTrack);
    expect(pct.style!.color, const Color(0xFF8E939B));
    unawaited(conn.dispose());
  });

  testWidgets('cover sheet: Position and Tilt tracks, HA tilt buttons', (tester) async {
    final (fake, env, conn) = await _house({
      'cover.blind': st('cover.blind', 'open', {
        'friendly_name': 'Blind',
        'current_position': 40,
        'current_tilt_position': 30,
        'supported_features': 255,
      }),
    });
    await tester.pumpWidget(_app(CoverCard(config: {'entity': 'cover.blind', 'height': 260}, env: env)));
    await tester.pump();
    await tester.longPress(find.byType(CoverCard));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Tilt'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('tilt-track')), matching: find.text('30%')), findsOneWidget);

    fake.calls.clear();
    await tester.tap(find.byIcon(MdiIcons.rotateLeft));
    await tester.tap(find.byIcon(MdiIcons.rotateRight));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.calls, [
      'cover.open_cover_tilt {"entity_id":"cover.blind"}',
      'cover.close_cover_tilt {"entity_id":"cover.blind"}',
    ]);

    fake.calls.clear();
    final tilt = find.byKey(const ValueKey('tilt-track'));
    await tester.tapAt(tester.getTopLeft(tilt) + Offset(tester.getSize(tilt).width / 2, tester.getSize(tilt).height * .25));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.calls.single, startsWith('cover.set_cover_tilt_position'));
    expect(_last(fake, 'cover.set_cover_tilt_position', 'tilt_position'), inInclusiveRange(74, 76));
    unawaited(conn.dispose());
  });

  testWidgets('button card: four across, painted from an attribute, custom icon, long-press opens the sheet',
      (tester) async {
    final (fake, env, conn) = await _house({
      'cover.pertemp': st('cover.pertemp', 'open', {
        'friendly_name': 'Persienn',
        'current_position': 62,
        'current_tilt_position': 30,
        'supported_features': 255,
        'upstatus': 'Purple',
        'downstatus': 'Black',
        'favstatus': 'White',
      }),
    });
    Map<String, dynamic> btn(String icon, String attr) =>
        {'entity': 'cover.pertemp', 'icon': icon, 'service': 'cover.stop_cover', 'color_attribute': attr};
    await tester.pumpWidget(_app(SizedBox(
      width: 480,
      child: ButtonCard(
        config: {
          'height': 120,
          'columns': 4,
          'show_name': false,
          'long_press': 'sheet',
          'colors': {'purple': '#a78bfa'},
          'buttons': [
            btn('custom:persienn öppen', 'upstatus'),
            btn('mdi:arrow-down', 'downstatus'),
            btn('mdi:star', 'favstatus'),
            btn('mdi:stop', 'none'),
          ],
        },
        env: env,
      ),
    )));
    await tester.pump();

    final boxes = tester
        .widgetList<Container>(find.descendant(of: find.byType(ButtonCard), matching: find.byType(Container)))
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .whereType<Color>()
        .toList();
    expect(boxes, contains(const Color(0xFFA78BFA)), reason: 'Purple, through the colors map');
    expect(boxes, contains(const Color(0xFFFFFFFF)), reason: 'White, as CSS names it');
    expect(find.byType(PathIcon), findsOneWidget, reason: 'the custom: icon is drawn from its path');
    // four tiles in one row
    final ys = tester.widgetList<RawGestureDetector>(find.byType(RawGestureDetector)).length;
    expect(ys, greaterThanOrEqualTo(4));

    await tester.tap(find.byType(PathIcon));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.calls.last, 'cover.stop_cover {"entity_id":"cover.pertemp"}');

    // the tick of the tap holds for feedback_ms, then the icon is back
    await tester.pump(const Duration(milliseconds: 1300));
    final before = fake.calls.length;
    await tester.longPress(find.byType(PathIcon));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Position'), findsOneWidget, reason: "the cover's own sheet");
    expect(fake.calls.length, before, reason: 'a long-press is not also a press');
    unawaited(conn.dispose());
  });

  test('colour names and icon paths', () {
    expect(parseColour('Purple'), const Color(0xFF800080));
    expect(parseColour('rebeccapurple'), const Color(0xFF663399));
    expect(parseColour('#abc'), const Color(0xFFAABBCC));
    expect(parseColour('not-a-colour'), isNull);
    final b = customIconPath('custom:persienn öppen')!.getBounds();
    expect(b.left, closeTo(1.563, .001));
    expect(b.top, closeTo(2.362, .001));
    expect(b.right, closeTo(21.562, .001));
    expect(b.bottom, closeTo(21.787, .001));
  });
  testWidgets('media, sideways: the name plate gets all the width the value plate leaves', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const title = 'A rather long song title that a browser card shows most of';
    final (_, env, conn) = await _house({
      'media_player.k': st('media_player.k', 'playing',
          {'friendly_name': 'Kitchen', 'media_title': title, 'media_artist': 'Someone', 'volume_level': .3}),
    });
    await tester.pumpWidget(_app(SizedBox(
      width: 456,
      child: MediaCard(
        config: {'entity': 'media_player.k', 'height': 120, 'fill_direction': 'horizontal'},
        env: env,
      ),
    )));
    await tester.pump();
    final name = tester.getRect(find.text(title));
    final value = tester.getRect(find.byType(ValueText));
    // the long name runs up to the value plate: its own padding (16) and the
    // gap (12) between them, where a Spacer used to take half the free width
    expect(value.left - name.right, inInclusiveRange(0, 40));
    unawaited(conn.dispose());
  });

  testWidgets('clock: clock_size sets the digits, clamped to 24-160', (tester) async {
    final (_, env, conn) = await _house({});
    // tall enough for 160px digits and the date under them
    double digits(Map<String, dynamic> cfg) {
      final t = tester.widget<Text>(find.byWidgetPredicate((w) => w is Text && w.textSpan != null).first);
      return t.style!.fontSize!;
    }

    for (final (cfg, want) in [
      (<String, dynamic>{}, 88.0),
      ({'clock_size': 120}, 120.0),
      ({'clock_size': 500}, 160.0),
      ({'clock_size': 4}, 24.0),
    ]) {
      await tester.pumpWidget(_app(ClockCard(key: UniqueKey(), config: {'height': 280, ...cfg}, env: env)));
      expect(digits(cfg), want);
    }
    await tester.pumpWidget(const SizedBox());
    unawaited(conn.dispose());
  });
  testWidgets('light: show_value false drops the number, the state line keeps it', (tester) async {
    final (_, env, conn) = await _house({
      'light.desk': st('light.desk', 'on', {'friendly_name': 'Desk', 'brightness': 128}),
    });
    for (final shown in [true, false]) {
      await tester.pumpWidget(_app(LightCard(
        key: UniqueKey(),
        config: {'entity': 'light.desk', 'height': 120, 'fill_direction': 'horizontal', 'show_value': shown},
        env: env,
      )));
      await tester.pump();
      expect(find.byType(ValueText), shown ? findsOneWidget : findsNothing);
      expect(find.text('On · 50%'), findsOneWidget);
    }
    unawaited(conn.dispose());
  });
}
