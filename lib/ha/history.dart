import 'dart:math' as math;

import 'connection.dart';

/// One period of a sensor: its middle (ms since epoch), mean, min and max.
class GraphPoint {
  const GraphPoint(this.t, this.v, this.lo, this.hi);
  final int t;
  final double v, lo, hi;
}

/// What HA said about a set of sensors over [start, end].
class GraphSeries {
  const GraphSeries({required this.start, required this.end, required this.step, required this.byId});
  final int start, end, step;
  final Map<String, List<GraphPoint>> byId;
}

/// A sensor's last hours, the way the web graph card gets them: HA's
/// long-term statistics, a mean, min and max per five minutes (per hour beyond
/// two days), for every sensor in one request. 24 hours is 288 points whatever
/// the sensor does - a power meter reporting every second costs what a
/// thermometer does. A sensor the recorder keeps no statistics for (no
/// state_class) comes from its recorded history, bucketed here into the same
/// periods, without holding up the others.
Future<GraphSeries> fetchSeries(HaConnection conn, List<String> ids, int hours, {DateTime? now}) async {
  final h = hours.clamp(1, 168);
  final hourly = h > 48;
  final step = hourly ? 3600000 : 300000;
  final end = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final start = end - h * 3600000;
  final startIso = DateTime.fromMillisecondsSinceEpoch(start, isUtc: true).toIso8601String();
  final byId = <String, List<GraphPoint>>{};

  int ms(Object? x) {
    if (x is num) return (x < 1e12 ? x * 1000 : x).round();
    return DateTime.tryParse('$x')?.millisecondsSinceEpoch ?? 0;
  }

  double? n(Object? x) => x is num && x.isFinite ? x.toDouble() : null;

  try {
    final res = await conn.send({
      'type': 'recorder/statistics_during_period',
      'start_time': startIso,
      'statistic_ids': ids,
      'period': hourly ? 'hour' : '5minute',
      'types': ['mean', 'min', 'max'],
    });
    for (final id in ids) {
      final rows = res is Map && res[id] is List ? res[id] as List : const [];
      byId[id] = [
        for (final r in rows.whereType<Map>())
          if (n(r['mean']) != null)
            GraphPoint(ms(r['start']) + step ~/ 2, n(r['mean'])!, n(r['min']) ?? n(r['mean'])!,
                n(r['max']) ?? n(r['mean'])!),
      ];
    }
  } catch (_) {
    // an older HA, or a recorder that is not there: history for all of them
  }

  final missing = [for (final id in ids) if ((byId[id] ?? const []).isEmpty) id];
  if (missing.isNotEmpty) {
    final res = await conn.send({
      'type': 'history/history_during_period',
      'start_time': startIso,
      'entity_ids': missing,
      'minimal_response': true,
      'no_attributes': true,
      'significant_changes_only': false,
    });
    for (final id in missing) {
      final rows = res is Map && res[id] is List ? res[id] as List : const [];
      byId[id] = _bucket(rows, start, end, step);
    }
  }
  return GraphSeries(start: start, end: end, step: step, byId: byId);
}

List<GraphPoint> _bucket(List rows, int start, int end, int step) {
  final samples = <(int, double)>[];
  for (final r in rows.whereType<Map>()) {
    final t = r['lu'] is num
        ? ((r['lu'] as num) * 1000).round()
        : r['lc'] is num
            ? ((r['lc'] as num) * 1000).round()
            : DateTime.tryParse('${r['last_updated'] ?? r['last_changed']}')?.millisecondsSinceEpoch;
    final v = double.tryParse('${r['s'] ?? r['state']}');
    if (t != null && v != null && v.isFinite) samples.add((t, v));
  }
  samples.sort((a, b) => a.$1.compareTo(b.$1));
  final out = <GraphPoint>[];
  var i = 0;
  double? last;
  for (var b = (start ~/ step) * step; b < end; b += step) {
    var sum = 0.0, count = 0;
    var lo = double.infinity, hi = double.negativeInfinity;
    while (i < samples.length && samples[i].$1 < b + step) {
      final v = samples[i].$2;
      if (samples[i].$1 >= b) {
        sum += v;
        count++;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
      last = v;
      i++;
    }
    // a quiet sensor holds its value: an empty bucket is the last one seen
    if (count > 0) {
      out.add(GraphPoint(b + step ~/ 2, sum / count, lo, hi));
    } else if (last != null) {
      out.add(GraphPoint(b + step ~/ 2, last, last, last));
    }
  }
  return out;
}

/// A round step that cuts [range] into about [n] parts: 1, 2 or 5 times a
/// power of ten, whichever comes closest. Not 2.5 - its lines land on 12.5
/// and 17.5, which read worse than a line every 2.
double niceStep(double range, int n) {
  final mag = math.pow(10, (math.log(range / n) / math.ln10).floor()).toDouble();
  var best = mag;
  for (final k in const [1, 2, 5, 10]) {
    if ((range / (k * mag) - n).abs() < (range / best - n).abs()) best = k * mag;
  }
  return best;
}

/// A label on an axis: its place as a fraction (from the top for values,
/// from the left for times) and its text.
class Tick {
  const Tick(this.f, this.label);
  final double f;
  final String label;
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Vertical grid lines at round local times: every hour over 6 h, every three
/// over a day, noon and midnight over three days, midnights over a week.
List<Tick> timeTicks(int t0, int t1, double hours) {
  final every = hours <= 6 ? 1 : hours <= 24 ? 3 : hours <= 72 ? 12 : 24;
  final first = DateTime.fromMillisecondsSinceEpoch(t0);
  var d = DateTime(first.year, first.month, first.day, (first.hour / every).ceil() * every);
  if (d.millisecondsSinceEpoch <= t0) d = DateTime(d.year, d.month, d.day, d.hour + every);
  final out = <Tick>[];
  while (d.millisecondsSinceEpoch < t1 && out.length < 40) {
    out.add(Tick(
      (d.millisecondsSinceEpoch - t0) / (t1 - t0),
      every >= 24 || (every == 12 && d.hour == 0) ? _days[d.weekday - 1] : '${d.hour.toString().padLeft(2, '0')}:00',
    ));
    d = DateTime(d.year, d.month, d.day, d.hour + every);
  }
  return out;
}

/// One line on the graph, in unit coordinates (0..1 across, 0..1 down) so
/// the painter scales it to whatever size it gets.
class GraphLine {
  const GraphLine(this.line, this.band);
  final List<(double, double)> line;

  /// The min-max band as (x, yTop, yBottom), or empty.
  final List<(double, double, double)> band;
}

/// Everything the painter and the labels need, for [lines] of (id, live
/// value) over [now - hours, now]. All lines share one scale, which snaps
/// outwards to round grid lines so the top and bottom are labelled values.
class GraphLayout {
  const GraphLayout({required this.lines, required this.yTicks, required this.xTicks, required this.lo, required this.hi});
  final List<GraphLine> lines;
  final List<Tick> yTicks, xTicks;
  final double lo, hi;

  static GraphLayout? of(GraphSeries s, int hours, List<(String, double?)> lines, {required bool band, DateTime? now}) {
    final t1 = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final t0 = t1 - hours.clamp(1, 168) * 3600000;
    final sets = [
      for (final (id, live) in lines) ((s.byId[id] ?? const <GraphPoint>[]).where((p) => p.t >= t0).toList(), live),
    ];
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final (pts, live) in sets) {
      for (final p in pts) {
        lo = math.min(lo, band ? p.lo : p.v);
        hi = math.max(hi, band ? p.hi : p.v);
      }
      if (live != null) {
        lo = math.min(lo, live);
        hi = math.max(hi, live);
      }
    }
    if (lo == double.infinity) return null;
    // about six bands between lines: 7-12 degrees gets a line every degree
    final span = hi - lo;
    final step = niceStep(span > 0 ? span : math.max(hi.abs() * .1, 1), 6);
    final bottom = (lo / step).floor() * step;
    var top = (hi / step).ceil() * step;
    if (top - bottom < step) top = bottom + step;
    double x(int t) => (t - t0) / (t1 - t0);
    double y(double v) => 1 - (v - bottom) / (top - bottom);
    final out = [
      for (final (pts, live) in sets)
        GraphLine(
          [for (final p in pts) (x(p.t), y(p.v)), if (live != null) (1.0, y(live))],
          band && pts.length > 1 ? [for (final p in pts) (x(p.t), y(p.hi), y(p.lo))] : const [],
        ),
    ];
    // labels carry as many decimals as the step needs: 0.2 steps read 20.2
    final dec = step >= 1 ? 0 : math.min(3, -((math.log(step) / math.ln10) + 1e-9).floor());
    final yt = <Tick>[];
    for (var v = bottom; v <= top + step / 2; v += step) {
      yt.add(Tick(1 - (v - bottom) / (top - bottom), (v.abs() < step / 1e6 ? 0.0 : v).toStringAsFixed(dec)));
    }
    return GraphLayout(lines: out, yTicks: yt, xTicks: timeTicks(t0, t1, (t1 - t0) / 3600000), lo: lo, hi: hi);
  }
}
