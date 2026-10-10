import 'package:flutter/widgets.dart';

/// Local value vs. incoming state, without a widget: the value under the
/// user's finger, or the one they just let go of. For `echoMs` after a change,
/// incoming state loses to it, so a slow round-trip can never yank the fill
/// backwards under a hand. The sheet a button card opens keeps one of these
/// of its own, since there is no card behind it.
class EchoBox {
  double? local;
  DateTime until = DateTime.fromMillisecondsSinceEpoch(0);
  bool dragging = false;

  double display(double entityValue) {
    if (local != null && (dragging || DateTime.now().isBefore(until))) return local!;
    local = null;
    return entityValue;
  }

  void hold(double v, int echoMs) {
    local = v;
    until = DateTime.now().add(Duration(milliseconds: echoMs));
  }
}

/// The same, for a card: `display()` is the one place that resolves it - read
/// values through it, never from the entity directly.
mixin EchoMixin<T extends StatefulWidget> on State<T> {
  final EchoBox echo = EchoBox();

  bool get dragging => echo.dragging;
  set dragging(bool v) => echo.dragging = v;

  double display(double entityValue) => echo.display(entityValue);

  /// During a drag: track the finger, no timers, no service calls.
  void setLocal(double v) => setState(() => echo.local = v);

  /// After a change was sent: keep showing it until HA has had time to echo.
  void holdLocal(double v, int echoMs) => setState(() => echo.hold(v, echoMs));

  /// For the sheet: whatever it changed, the card underneath shows too.
  void echoChanged() {
    if (mounted) setState(() {});
  }
}
