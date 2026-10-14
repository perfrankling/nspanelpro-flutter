import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/color.dart';
import 'theme.dart';

class SheetAction {
  const SheetAction({required this.label, this.icon, this.primary = false, required this.run});
  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback run;
}

/// A second track beside the main one: a cover's tilt.
class SheetTrack {
  const SheetTrack({required this.label, required this.value, this.fromTop = false, this.onInput, this.onCommit});
  final String label;
  final double value;
  final bool fromTop;
  final ValueChanged<double>? onInput;
  final ValueChanged<double>? onCommit;
}

/// Everything the sheet shows, as of now. The card hands over a function that
/// builds one of these, and the sheet calls it again whenever the entity
/// changes - so the next track, play turning to pause, a volume set from
/// elsewhere all show while it is open, as they do in the web sheet.
class SheetSpec {
  const SheetSpec({
    required this.title,
    required this.state,
    required this.value,
    required this.accent,
    this.fromTop = false,
    this.step = 5,
    this.actions = const [],
    this.onInput,
    this.onCommit,
    this.onTap,
    this.muted = false,
    this.label = '',
    this.tilt,
    this.stepUp,
    this.stepDown,
  });

  final String title;
  final String state;
  final double value;
  final Color accent;
  final bool fromTop;
  final double step;
  final List<SheetAction> actions;
  final ValueChanged<double>? onInput;
  final ValueChanged<double>? onCommit;

  /// A tap on the main track, instead of setting the value there: the media
  /// sheet's mute. A drag still sets the value.
  final VoidCallback? onTap;

  /// The value is shown in grey: a muted player.
  final bool muted;

  /// Names the main track when there is a second one ("Position").
  final String label;
  final SheetTrack? tilt;

  /// In place of the ± steps: a cover's tilt open / close.
  final SheetAction? stepUp;
  final SheetAction? stepDown;
}

const _mutedGrey = Color(0xFF8E939B);

/// The long-press control surface: an absolute slider (two for a cover with
/// tilt), big ± steps or the card's own two buttons, and up to four actions.
/// The caller keeps the echo window, so the card underneath agrees with it.
Future<void> showControlSheet(
  BuildContext context, {
  required SheetSpec Function() spec,
  Listenable? listen,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: Ns.ground.withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => listen == null
        ? _Sheet(spec: spec())
        : AnimatedBuilder(animation: listen, builder: (_, _) => _Sheet(spec: spec())),
  );
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.spec});
  final SheetSpec spec;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  SheetSpec get s => widget.spec;
  late double _v = s.value;
  late double _t = s.tilt?.value ?? 0;
  bool _dragging = false;
  bool _tilting = false;

  @override
  void didUpdateWidget(_Sheet old) {
    super.didUpdateWidget(old);
    // a fresh state from HA, but never under a finger on that track
    if (!_dragging) _v = s.value;
    if (!_tilting && s.tilt != null) _t = s.tilt!.value;
  }

  void _set(double v, {bool commit = false}) {
    _v = v.clamp(0.0, 1.0);
    setState(() {});
    if (commit) {
      s.onCommit?.call(_v);
    } else {
      s.onInput?.call(_v);
    }
  }

  void _setTilt(double v, {bool commit = false}) {
    _t = v.clamp(0.0, 1.0);
    setState(() {});
    final t = s.tilt;
    if (commit) {
      t?.onCommit?.call(_t);
    } else {
      t?.onInput?.call(_t);
    }
  }

  void _stepBy(double delta) {
    HapticFeedback.lightImpact();
    _set(_v + delta / 100, commit: true);
  }

  Widget _side(SheetAction? a, double delta, IconData fallback) => Expanded(
        child: _Square(
          onTap: a != null
              ? () {
                  HapticFeedback.lightImpact();
                  a.run();
                }
              : () => _stepBy(delta),
          child: Icon(a?.icon ?? fallback, color: Ns.text, size: a != null ? 40 : 34),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tilt = s.tilt;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Ns.text, fontSize: 22, fontWeight: FontWeight.w700)),
                        Text(s.state,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Ns.muted, fontSize: 15, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  _Square(
                    size: 56,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: Ns.text, size: 26),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _Track(
                        key: const ValueKey('main-track'),
                        value: _v,
                        accent: s.accent,
                        fromTop: s.fromTop,
                        dragging: _dragging,
                        label: tilt != null ? s.label : '',
                        valueColor: s.muted ? _mutedGrey : Ns.text,
                        onTap: s.onTap == null
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                s.onTap!();
                              },
                        onValue: (v) => _set(v, commit: s.onTap == null && !_dragging),
                        onDragState: (d) {
                          setState(() => _dragging = d);
                          if (!d) _set(_v, commit: true);
                        },
                      ),
                    ),
                    if (tilt != null) ...[
                      const SizedBox(width: 14),
                      Expanded(
                        child: _Track(
                          key: const ValueKey('tilt-track'),
                          value: _t,
                          accent: s.accent,
                          fromTop: tilt.fromTop,
                          dragging: _tilting,
                          label: tilt.label,
                          valueColor: Ns.text,
                          onValue: (v) => _setTilt(v, commit: !_tilting),
                          onDragState: (d) {
                            setState(() => _tilting = d);
                            if (!d) _setTilt(_t, commit: true);
                          },
                        ),
                      ),
                    ],
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 96,
                      child: Column(
                        children: [
                          _side(s.stepUp, s.step, Icons.add),
                          const SizedBox(height: 14),
                          _side(s.stepDown, -s.step, Icons.remove),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (s.actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 76,
                  child: Row(
                    children: [
                      for (var i = 0; i < s.actions.length && i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _Square(
                            color: s.actions[i].primary ? s.accent : Ns.surface,
                            // No action closes the sheet: it updates in place,
                            // so the result shows here, and a wrong tap is one
                            // more tap to undo - not a long-press to come back.
                            // The X and the barrier close it.
                            onTap: () {
                              HapticFeedback.lightImpact();
                              s.actions[i].run();
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (s.actions[i].icon != null)
                                  Icon(s.actions[i].icon, size: 24, color: s.actions[i].primary ? Ns.ground : Ns.text),
                                const SizedBox(height: 4),
                                Text(s.actions[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: s.actions[i].primary ? Ns.ground : Ns.text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One absolute track: the touch point is the value. With an onTap, a touch
/// is not a value yet - a tap runs onTap, a drag sets the value - otherwise
/// the first touch already sets it, as it always did.
class _Track extends StatelessWidget {
  const _Track({
    super.key,
    required this.value,
    required this.accent,
    required this.fromTop,
    required this.dragging,
    required this.label,
    required this.valueColor,
    required this.onValue,
    required this.onDragState,
    this.onTap,
  });

  final double value;
  final Color accent;
  final bool fromTop;
  final bool dragging;
  final String label;
  final Color valueColor;
  final ValueChanged<double> onValue;
  final ValueChanged<bool> onDragState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stops = tintStops(accent);
    return LayoutBuilder(
      builder: (_, box) {
        final h = box.maxHeight;
        // the top of the track is always "more"; fromTop only moves the fill
        double fromY(double y) => (1 - y / h).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onTap == null ? (d) => onValue(fromY(d.localPosition.dy)) : null,
          onTap: onTap,
          onVerticalDragStart: (d) {
            onDragState(true);
            onValue(fromY(d.localPosition.dy));
          },
          onVerticalDragUpdate: (d) => onValue(fromY(d.localPosition.dy)),
          onVerticalDragEnd: (_) => onDragState(false),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Ns.surface, borderRadius: BorderRadius.circular(20)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: value),
                  duration: dragging ? Duration.zero : const Duration(milliseconds: 120),
                  builder: (_, v, child) => FractionalTranslation(
                    translation: fromTop ? Offset(0, -v) : Offset(0, 1 - v),
                    child: child,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [accent, stops.strong],
                      ),
                    ),
                  ),
                ),
                if (label.isNotEmpty)
                  Positioned(
                    top: 14,
                    left: 0,
                    right: 0,
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xC7FFFFFF), fontSize: 15, fontWeight: FontWeight.w600, shadows: Ns.shadow)),
                  ),
                Center(
                  child: Text('${(value * 100).round()}%',
                      style: TextStyle(
                          color: valueColor,
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          fontFeatures: Ns.tabular,
                          shadows: Ns.shadow)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Square extends StatelessWidget {
  const _Square({required this.onTap, required this.child, this.size, this.color = Ns.surface});
  final VoidCallback onTap;
  final Widget child;
  final double? size;
  final Color color;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
          child: child,
        ),
      );
}
