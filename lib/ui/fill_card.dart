import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/color.dart';
import '../util/custom_icons.dart';
import 'theme.dart';

class ChipSpec {
  const ChipSpec({required this.label, this.icon, required this.onTap, this.disabled = false});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool disabled;
}

/// The control surface every "set a level" card is built on: a tinted block
/// that fills the card to the value, the level line on its edge, text on top,
/// and the gesture engine - drag anywhere to set, tap, long-press.
///
/// What runs during a drag: one transform. The fill is a FractionalTranslation
/// of a full-size block, so tracking the finger is compositor work, and the
/// parent owns the value so nothing here allocates per frame beyond the
/// rebuild itself. Nothing is sent to HA until the finger lifts.
class FillCard extends StatefulWidget {
  const FillCard({
    super.key,
    required this.height,
    required this.accent,
    required this.fill,
    required this.fillOpacity,
    required this.title,
    required this.sub,
    this.fromTop = false,
    this.horizontal = false,
    this.solid = false,
    this.dragSign = 1,
    this.on = false,
    this.broken = false,
    this.leading,
    this.value,
    this.chips = const [],
    this.chips2 = const [],
    this.opaqueChips = false,
    this.dragTravel,
    this.onTap,
    this.onLongPress,
    this.onDragValue,
    this.onDragEnd,
  });

  final double height;
  final Color accent;
  final double fill;
  final double fillOpacity;
  final bool fromTop;

  /// fill_direction: horizontal. The fill runs from the left, a sideways drag
  /// sets it (the vertical one goes to whatever holds the card), and the name
  /// sits beside the icon on a plate in the card's own colour, centred in the
  /// height the chips leave. With [fromTop] the block is a cover's blind,
  /// coming in from the left.
  final bool horizontal;

  /// fill_style: solid - the accent as given, opaque, instead of the tint.
  final bool solid;

  /// +1: a drag the way the fill grows raises the value. A sideways cover
  /// passes -1: its fill is the blind, and dragging right brings it down.
  final double dragSign;
  final bool on;
  final bool broken;
  final Widget? leading;
  final Widget? value;
  final String title;
  final String sub;
  final List<ChipSpec> chips;
  final List<ChipSpec> chips2;
  final bool opaqueChips;
  final double? dragTravel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<double>? onDragValue;
  final ValueChanged<double>? onDragEnd;

  @override
  State<FillCard> createState() => _FillCardState();
}

class _FillCardState extends State<FillCard> {
  bool _dragging = false;
  double _start = 0;
  double _d = 0;
  double _last = 0;

  /// Whether the drag has moved along its axis. A recogniser can win the arena
  /// by default when the finger lifts with nothing else claiming it - a
  /// vertical swipe across a horizontal card - and that is not a drag: it
  /// must not commit anything.
  bool _moved = false;

  bool get _interactive => !widget.broken;

  void _onDragStart(DragStartDetails d) {
    _dragging = true;
    _start = widget.fill;
    _d = 0;
    _last = widget.fill;
    _moved = false;
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // _d is the drag in the direction the fill grows: right, or up
    final step = widget.horizontal ? d.delta.dx : -d.delta.dy;
    if (step == 0 && !_moved) return;
    if (!_moved) HapticFeedback.selectionClick();
    _moved = true;
    _d += step;
    final travel = widget.dragTravel ?? (widget.horizontal ? context.size?.width : null) ?? widget.height;
    _last = (_start + widget.dragSign * _d / travel).clamp(0.0, 1.0);
    widget.onDragValue?.call(_last);
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    if (_moved) {
      HapticFeedback.lightImpact();
      widget.onDragEnd?.call(_last);
    }
    setState(() {});
  }

  void _onDragCancel() {
    _dragging = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final stops = tintStops(widget.accent);
    final canDrag = _interactive && widget.onDragValue != null;
    final vDrag = canDrag && !widget.horizontal;
    final hDrag = canDrag && widget.horizontal;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _interactive && widget.onTap != null
          ? () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      onLongPress: _interactive && widget.onLongPress != null
          ? () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            }
          : null,
      onVerticalDragStart: vDrag ? _onDragStart : null,
      onVerticalDragUpdate: vDrag ? _onDragUpdate : null,
      onVerticalDragEnd: vDrag ? _onDragEnd : null,
      onVerticalDragCancel: vDrag ? _onDragCancel : null,
      onHorizontalDragStart: hDrag ? _onDragStart : null,
      onHorizontalDragUpdate: hDrag ? _onDragUpdate : null,
      onHorizontalDragEnd: hDrag ? _onDragEnd : null,
      onHorizontalDragCancel: hDrag ? _onDragCancel : null,
      child: Opacity(
        opacity: widget.broken ? .45 : 1,
        child: Container(
          height: widget.height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Ns.surface,
            borderRadius: CardRadius.card(context),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // the fill: a block that slides. Transform only.
              TweenAnimationBuilder<double>(
                tween: Tween(end: widget.fill),
                duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => FractionalTranslation(
                  translation: widget.horizontal
                      ? (widget.fromTop ? Offset(-v, 0) : Offset(v - 1, 0))
                      : (widget.fromTop ? Offset(0, -v) : Offset(0, 1 - v)),
                  child: child,
                ),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: widget.fillOpacity),
                  duration: const Duration(milliseconds: 180),
                  builder: (_, o, _) => _FillBlock(
                    strong: widget.solid
                        ? widget.accent.withValues(alpha: o)
                        : stops.strong.withValues(alpha: stops.strong.a * o),
                    weak: widget.solid
                        ? widget.accent.withValues(alpha: o)
                        : stops.weak.withValues(alpha: stops.weak.a * o),
                    line: widget.accent.withValues(alpha: o),
                    fromTop: widget.fromTop,
                    horizontal: widget.horizontal,
                  ),
                ),
              ),
              if (widget.broken)
                const Positioned(
                  top: 12,
                  right: 14,
                  child: Text('OFFLINE',
                      style: TextStyle(
                          color: Ns.danger, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: widget.horizontal ? _sideways() : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.leading != null) widget.leading!,
                        const Spacer(),
                        if (widget.value != null) widget.value!,
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                        Text(widget.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
                        if (widget.chips.isNotEmpty)
                          ChipRow(chips: widget.chips, on: widget.on, opaque: widget.opaqueChips),
                        if (widget.chips2.isNotEmpty)
                          ChipRow(chips: widget.chips2, on: widget.on, opaque: widget.opaqueChips),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The horizontal layout: icon and name on one plate, the value on another,
  /// both in the card's own colour so they only show where the fill runs under
  /// them, centred in the height above the chips. On a card too low for the
  /// plates they overflow evenly up and down rather than off the bottom.
  Widget _sideways() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: OverflowBox(
              minHeight: 0,
              maxHeight: double.infinity,
              // The value plate takes what it needs and the name's plate every
              // other pixel, as the web card's flex: 0 1 auto does; a Spacer
              // here would split the free width and halve the name.
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                      decoration: BoxDecoration(color: Ns.surface, borderRadius: CardRadius.inner(context, 20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.leading != null) widget.leading!,
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                                Text(widget.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.value != null)
                    Container(
                      margin: const EdgeInsets.only(left: 12),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      decoration: BoxDecoration(color: Ns.surface, borderRadius: CardRadius.inner(context, 16)),
                      child: widget.value,
                    ),
                ],
              ),
            ),
          ),
          if (widget.chips.isNotEmpty)
            ChipRow(chips: widget.chips, on: widget.on, opaque: widget.opaqueChips, horizontal: true),
          if (widget.chips2.isNotEmpty)
            ChipRow(chips: widget.chips2, on: widget.on, opaque: widget.opaqueChips, horizontal: true),
        ],
      );
}

/// How many chip rows a horizontal card has room for, in order: each is 56px
/// plus a 12px gap, and the plate row keeps 56px of the height inside the
/// padding. A vertical card shows them all, as it always has.
int chipRowsThatFit(double height, {required bool horizontal}) {
  if (!horizontal) return 2;
  final room = height - 36 - 56;
  return room < 68 ? 0 : (room < 136 ? 1 : 2);
}

class _FillBlock extends StatelessWidget {
  const _FillBlock({
    required this.strong,
    required this.weak,
    required this.line,
    required this.fromTop,
    this.horizontal = false,
  });
  final Color strong, weak, line;
  final bool fromTop, horizontal;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              // strongest at the level edge: the top, or sideways the right
              gradient: LinearGradient(
                begin: horizontal ? Alignment.centerRight : Alignment.topCenter,
                end: horizontal ? Alignment.centerLeft : Alignment.bottomCenter,
                colors: [strong, weak],
              ),
            ),
          ),
          // the level itself, unmistakable at arm's length
          if (horizontal)
            Positioned(top: 0, bottom: 0, right: 0, width: 3, child: ColoredBox(color: line))
          else
            Positioned(
              left: 0,
              right: 0,
              top: fromTop ? null : 0,
              bottom: fromTop ? 0 : null,
              height: 3,
              child: ColoredBox(color: line),
            ),
        ],
      );
}

const nameStyle = TextStyle(
    color: Ns.text, fontSize: 22, fontWeight: FontWeight.w600, height: 28 / 22, letterSpacing: -.2, shadows: Ns.shadow);
const subStyle = TextStyle(
    color: Color(0xB8FFFFFF), fontSize: 15, fontWeight: FontWeight.w500, height: 20 / 15, shadows: Ns.shadow);

/// The big number in the top-right of a control card: `68` and a smaller `%`.
class ValueText extends StatelessWidget {
  const ValueText(this.value, {super.key, this.unit = '', this.size = 40, this.color = Ns.text, this.caption});
  final String value;
  final String unit;
  final double size;

  /// Ns.text, or grey for a muted player.
  final Color color;

  /// A line under the number: the media card's `0–30` while the scale is zoomed.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final number = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: value,
                style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                    height: 1,
                    color: color,
                    fontFeatures: Ns.tabular,
                    shadows: Ns.shadow)),
            if (unit.isNotEmpty)
              TextSpan(
                  text: unit,
                  style: TextStyle(
                      fontSize: size / 2,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: .65),
                      shadows: Ns.shadow)),
          ]),
        ),
      );
    if (caption == null) return number;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        number,
        const SizedBox(height: 4),
        Text(caption!, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600, shadows: Ns.shadow)),
      ],
    );
  }
}

/// The rounded square that holds a card's icon.
class IconBox extends StatelessWidget {
  const IconBox(this.icon, {super.key, this.on = false, this.color, this.name});
  final IconData icon;
  final bool on;
  final Color? color;

  /// The configured name, when it may be a custom: icon drawn from a path;
  /// [icon] is what shows when it is not one.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final path = customIconPath(name);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: on ? .16 : .10),
        borderRadius: CardRadius.inner(context, 16),
      ),
      child: path != null
          ? Center(child: PathIcon(path, size: 30, color: color ?? Ns.text))
          : Icon(icon, size: 30, color: color ?? Ns.text),
    );
  }
}

/// A row of 56px chips - presets, transport, favourites.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.chips, this.on = false, this.opaque = false, this.horizontal = false});
  final List<ChipSpec> chips;
  final bool on;
  final bool opaque;

  /// The card's drag axis: a chip claims that one only, so a drag started on
  /// a chip never moves the level and the other axis still reaches the pager.
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final bg = opaque
        ? Ns.surface2
        : (on ? Colors.black.withValues(alpha: .34) : Colors.white.withValues(alpha: .10));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _Chip(spec: chips[i], bg: bg, horizontal: horizontal)),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.spec, required this.bg, this.horizontal = false});
  final ChipSpec spec;
  final Color bg;
  final bool horizontal;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: spec.disabled
            ? null
            : () {
                HapticFeedback.lightImpact();
                spec.onTap();
              },
        // Claim the gestures the card would otherwise take from a chip: a
        // drag or hold that starts on a button should not move the level.
        onVerticalDragStart: horizontal ? null : (_) {},
        onHorizontalDragStart: horizontal ? (_) {} : null,
        onLongPress: () {},
        child: Opacity(
          opacity: spec.disabled ? .35 : 1,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: CardRadius.inner(context, 14)),
            child: spec.icon != null && spec.label.isEmpty
                ? Icon(spec.icon, size: 26, color: Colors.white)
                : Text(spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      );
}
