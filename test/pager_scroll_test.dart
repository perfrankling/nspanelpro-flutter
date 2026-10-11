import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/light_card.dart';
import 'package:nspanel_app/cards/registry.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/pager.dart';

import 'connection_test.dart' show FakeHa, st;

/// A page taller than the panel scrolls, as it does in a browser - but a
/// vertical drag on a card that takes vertical drags is still that card's.
void main() {
  testWidgets('a tall page scrolls from a sideways card; a vertical card keeps its drag; a short page does not scroll',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 480));
    final fake = FakeHa({
      'light.a': st('light.a', 'on', {'friendly_name': 'Sideways', 'brightness': 128}),
      'light.b': st('light.b', 'on', {'friendly_name': 'Upright', 'brightness': 128}),
    });
    final states = HaStates();
    final conn = HaConnection(transportFactory: () async => fake, token: 'good', states: states);
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future.timeout(const Duration(seconds: 2));
    final env = PanelEnv(states: states, conn: conn, settings: Settings(url: 'http://x', token: 't'));

    Map<String, dynamic> sideways(int n) =>
        {'type': 'custom:nspanel-light-card', 'entity': 'light.a', 'title': 'S$n', 'height': 140, 'fill_direction': 'horizontal', 'show_presets': false};
    final tall = buildCard({
      'type': 'vertical-stack',
      'cards': [
        sideways(1),
        {'type': 'custom:nspanel-light-card', 'entity': 'light.b', 'title': 'Upright', 'height': 200, 'show_presets': false},
        sideways(2),
        sideways(3),
      ],
    }, env);
    final short = buildCard({'type': 'vertical-stack', 'cards': [sideways(9)]}, env);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PanelPager(pages: [tall, short]))));
    await tester.pump();
    final scroller = find.byType(SingleChildScrollView).first;
    double offset() => tester.widget<SingleChildScrollView>(scroller).controller?.offset ??
        Scrollable.of(tester.element(find.text('S1'))).position.pixels;

    expect(find.text('S3'), findsOneWidget);
    expect(tester.getTopLeft(find.text('S3')).dy, greaterThan(480), reason: 'below the fold to start with');

    // a vertical drag on a sideways card is the page's
    await tester.drag(find.text('S1'), const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 50));
    expect(offset(), greaterThan(200));
    expect(tester.getTopLeft(find.text('S3')).dy, lessThan(480), reason: 'scrolled into view');
    expect(fake.calls, isEmpty, reason: 'scrolling sends nothing to HA');

    // a vertical drag on an upright card is the card's: it dims, the page stays
    final before = offset();
    await tester.drag(find.byType(LightCard).at(1), const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 50));
    expect(offset(), before, reason: 'the card took the drag');
    expect(fake.calls.single, startsWith('light.turn_on {"entity_id":"light.b"'));

    // and a sideways swipe still turns the page - from a card that does not
    // take sideways drags itself, here the visible part of the upright one
    final upright = tester.getRect(find.byType(LightCard).at(1));
    await tester.flingFrom(Offset(upright.center.dx, upright.bottom - 20), const Offset(-300, 0), 1000);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('S9'), findsOneWidget);
    final pos = Scrollable.of(tester.element(find.text('S9')), axis: Axis.vertical).position;
    expect(pos.maxScrollExtent, 0, reason: 'a page that fits has nothing to scroll');

    unawaited(conn.dispose());
  });
}
