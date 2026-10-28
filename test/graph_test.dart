import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/registry.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/history.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/graph.dart';
import 'package:nspanel_app/ui/page_scope.dart';

import 'connection_test.dart' show FakeHa, st;

/// The graph card, the full-screen graph and the sums behind them - the same
/// rules as the web card's, against a fake HA's statistics and history.

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

/// Five-minute statistics for the last [hours], a slow wave around [mid].
List<Map<String, dynamic>> _stats(double mid, {int hours = 24, double swing = 2.5}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final start = now - hours * 3600000;
  return [
    for (var t = (start ~/ 300000) * 300000; t < now - 300000; t += 300000)
      () {
        final v = mid + swing * ((t ~/ 300000) % 288 - 144) / 144;
        return {'start': t, 'end': t + 300000, 'mean': v, 'min': v - .2, 'max': v + .2};
      }(),
  ];
}

List<String> _types(FakeHa f, String type) => [
      for (final m in f.sent)
        if (m['type'] == type) '${m['statistic_ids'] ?? m['entity_ids']} ${m['period'] ?? ''}'.trim(),
    ];

void main() {
  group('the sums', () {
    test('round steps of 1, 2 or 5, about six bands', () {
      expect(niceStep(5, 6), 1, reason: '7-12 degrees: a line every degree');
      expect(niceStep(12.9, 6), 2, reason: 'never 2.5: its lines land on 12.5');
      expect(niceStep(3093, 6), 500);
      expect(niceStep(1.5, 6), closeTo(.2, 1e-9));
    });

    test('a 7-12 degree day: gridlines every degree, labelled, the range snapped to them', () {
      final now = DateTime.now();
      final t = now.millisecondsSinceEpoch;
      final s = GraphSeries(start: t - 86400000, end: t, step: 300000, byId: {
        'sensor.out': [
          GraphPoint(t - 80000000, 7.2, 7.2, 7.2),
          GraphPoint(t - 40000000, 11.8, 11.8, 11.8),
        ],
      });
      final l = GraphLayout.of(s, 24, [('sensor.out', 9.5)], band: false, now: now)!;
      expect([for (final k in l.yTicks) k.label], ['7', '8', '9', '10', '11', '12']);
      expect(l.yTicks.first.f, 1, reason: 'the bottom line is the bottom edge');
      expect(l.yTicks.last.f, 0);
      final end = l.lines.single.line.last;
      expect(end.$1, 1.0, reason: 'the live value ends the line at now');
      expect(end.$2, closeTo(.5, 1e-9), reason: '9.5 is half way up 7-12');
      final times = [for (final k in l.xTicks) k.label];
      expect(times.length, inInclusiveRange(7, 8), reason: 'every three hours over a day');
      expect(times.every((x) => RegExp(r'^\d\d:00$').hasMatch(x) && int.parse(x.substring(0, 2)) % 3 == 0), isTrue,
          reason: '$times');
    });
  });

  test('fetch: one statistics request for every sensor; history only for the one without', () async {
    final (fake, env, conn) = await _house({
      'sensor.out': st('sensor.out', '9.5', {'unit_of_measurement': '°C'}),
      'sensor.diy': st('sensor.diy', '21', {'unit_of_measurement': '°C'}),
    });
    fake.statistics['sensor.out'] = _stats(9.5);
    final now = DateTime.now().millisecondsSinceEpoch;
    fake.history['sensor.diy'] = [
      {'s': '20.0', 'lu': (now - 7200000) / 1000},
      {'s': '22.0', 'lu': (now - 3600000) / 1000},
      {'s': 'unavailable', 'lu': (now - 1800000) / 1000},
    ];
    final s = await fetchSeries(conn, ['sensor.out', 'sensor.diy'], 24);
    expect(_types(fake, 'recorder/statistics_during_period'), ['[sensor.out, sensor.diy] 5minute']);
    expect(_types(fake, 'history/history_during_period'), ['[sensor.diy]']);
    expect(s.byId['sensor.out']!.length, greaterThan(280));
    final diy = s.byId['sensor.diy']!;
    expect(diy.first.v, 20, reason: 'bucketed from the first sample');
    expect(diy.last.v, 22, reason: 'a quiet sensor holds its last value; "unavailable" is not a number');

    await fetchSeries(conn, ['sensor.out'], 168);
    expect(_types(fake, 'recorder/statistics_during_period').last, '[sensor.out] hour', reason: 'a week is hourly');
    unawaited(conn.dispose());
  });

  testWidgets('graph card: two sensors from one request, only while on screen', (tester) async {
    final (fake, env, conn) = await _house({
      'sensor.out': st('sensor.out', '9.5', {'friendly_name': 'Out', 'unit_of_measurement': '°C'}),
      'sensor.in': st('sensor.in', '20.4', {'friendly_name': 'In', 'unit_of_measurement': '°C'}),
    });
    fake.statistics['sensor.out'] = _stats(9.5);
    fake.statistics['sensor.in'] = _stats(20.4);
    final shown = ValueNotifier(1);
    final card = buildCard({
      'type': 'custom:nspanel-graph-card',
      'height': 220,
      'entities': [
        {'entity': 'sensor.out', 'name': 'Outside'},
        {'entity': 'sensor.in', 'name': 'Inside', 'color': '#ff0000'},
      ],
    }, env);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageScope(index: 0, shown: shown, awake: ValueNotifier(true), child: SizedBox(width: 456, child: card)),
      ),
    ));
    await tester.pump();
    expect(_types(fake, 'recorder/statistics_during_period'), isEmpty, reason: 'page 1 is showing, not this one');

    shown.value = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_types(fake, 'recorder/statistics_during_period'), ['[sensor.out, sensor.in] 5minute']);
    expect(find.text('Outside'), findsOneWidget);
    expect(find.text('Inside'), findsOneWidget);
    expect(find.text('↑ 12.0'), findsNothing, reason: 'high and low are one sensor\'s');
    expect(find.text('24 h'), findsOneWidget);

    // off screen and back within five minutes: no second request
    shown.value = 1;
    await tester.pump();
    shown.value = 0;
    await tester.pump(const Duration(milliseconds: 50));
    expect(_types(fake, 'recorder/statistics_during_period').length, 1);

    await tester.pumpWidget(const SizedBox());
    unawaited(conn.dispose());
  });

  testWidgets('long-press a sensor card: its graph full-screen, ranges, the X closes it', (tester) async {
    final (fake, env, conn) = await _house({
      'sensor.out': st('sensor.out', '9.5', {'friendly_name': 'Out', 'unit_of_measurement': '°C'}),
    });
    fake.statistics['sensor.out'] = _stats(9.5);
    await tester.binding.setSurfaceSize(const Size(480, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: buildCard({'type': 'custom:nspanel-sensor-card', 'entity': 'sensor.out', 'height': 140}, env)),
    ));
    await tester.pump();
    await tester.longPress(find.text('Out'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('7 d'), findsOneWidget, reason: 'the full-screen graph is open');
    expect(_types(fake, 'recorder/statistics_during_period'), ['[sensor.out] 5minute']);
    expect(find.textContaining('↑'), findsOneWidget, reason: 'one sensor: its high and low');

    await tester.tap(find.text('7 d'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_types(fake, 'recorder/statistics_during_period').last, '[sensor.out] hour');

    await tester.tap(find.byIcon(Icons.close));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('7 d'), findsNothing);
    unawaited(conn.dispose());
  });

  testWidgets('long_press: none and more_info: false leave the sensor card alone', (tester) async {
    final (fake, env, conn) = await _house({
      'sensor.out': st('sensor.out', '9.5', {'friendly_name': 'Out'}),
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: buildCard(
            {'type': 'custom:nspanel-sensor-card', 'entity': 'sensor.out', 'long_press': 'none', 'more_info': false},
            env),
      ),
    ));
    await tester.pump();
    await tester.longPress(find.text('Out'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('7 d'), findsNothing);
    expect(fake.sent.where((m) => '${m['type']}'.startsWith('recorder')), isEmpty);
    unawaited(conn.dispose());
  });

  test('colours: accent first, then amber, green, violet, unless an item names its own', () {
    const accent = Color(0xFF123456);
    expect(graphColour(null, 0, accent), accent);
    expect(graphColour(null, 1, accent), isNot(accent));
    expect(graphColour(const Color(0xFFFF0000), 1, accent), const Color(0xFFFF0000));
  });
  testWidgets('graph card built before HA answers: no "no history", and it asks again when HA comes up',
      (tester) async {
    // as on the panel at start: the dashboard is drawn from the cached
    // config while the connection is still being made
    final fake = FakeHa({
      'sensor.out': st('sensor.out', '9.5', {'friendly_name': 'Out', 'unit_of_measurement': '°C'}),
    });
    fake.statistics['sensor.out'] = _stats(9.5);
    final states = HaStates();
    final conn = HaConnection(transportFactory: () async => fake, token: 'good', states: states);
    final env = PanelEnv(states: states, conn: conn, settings: Settings(url: 'http://x', token: 't'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 456, child: buildCard({'type': 'custom:nspanel-graph-card', 'entity': 'sensor.out'}, env)),
      ),
    ));
    await tester.pump();
    expect(find.text('No history from Home Assistant'), findsNothing, reason: 'not connected is not an answer');

    await tester.runAsync(() async {
      final ready = Completer<void>();
      conn.onReady = ready.complete;
      await conn.start();
      await ready.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_types(fake, 'recorder/statistics_during_period'), ['[sensor.out] 5minute'],
        reason: 'asked again the moment HA came online, not five minutes later');
    expect(find.text('No history from Home Assistant'), findsNothing);
    expect(find.textContaining('↑'), findsOneWidget, reason: 'the graph is there: its high and low');

    await tester.pumpWidget(const SizedBox());
    unawaited(conn.dispose());
  });
  testWidgets('a tap opens the graph too - the app has no more-info; more_info: false turns that off',
      (tester) async {
    final (_, env, conn) = await _house({
      'sensor.out': st('sensor.out', '9.5', {'friendly_name': 'Out', 'unit_of_measurement': '°C'}),
    });
    await tester.binding.setSurfaceSize(const Size(480, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<bool> tapOpens(Map<String, dynamic> cfg, Finder target) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 456, child: buildCard(cfg, env)))));
      await tester.pump();
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 300));
      final open = find.text('7 d').evaluate().isNotEmpty;
      if (open) {
        await tester.tap(find.byIcon(Icons.close));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      return open;
    }

    final sensor = {'type': 'custom:nspanel-sensor-card', 'entity': 'sensor.out', 'height': 140};
    expect(await tapOpens(sensor, find.text('Out')), isTrue);
    expect(await tapOpens({...sensor, 'more_info': false}, find.text('Out')), isFalse);
    final sensors = {
      'type': 'custom:nspanel-sensors-card',
      'show_icons': false,
      'entities': [
        {'entity': 'sensor.out', 'name': 'Outside'},
        {'clock': true},
      ],
    };
    expect(await tapOpens(sensors, find.text('Outside')), isTrue);
    expect(await tapOpens(sensors, find.text('Time')), isFalse, reason: 'the clock reading has no history');
    final graph = {'type': 'custom:nspanel-graph-card', 'entity': 'sensor.out', 'height': 200};
    expect(await tapOpens(graph, find.text('24 h')), isTrue);
    expect(await tapOpens({...graph, 'more_info': false}, find.text('24 h')), isFalse);

    await tester.pumpWidget(const SizedBox());
    unawaited(conn.dispose());
  });
}
