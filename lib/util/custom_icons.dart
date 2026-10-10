import 'package:flutter/widgets.dart';

/// The owner's custom: icons, the same paths as icons/custom-icons.js in the
/// cards repo: one path each in a 24x24 viewBox, keyed by the name a config
/// uses, prefix included. In HA a custom-icons integration serves them; the
/// app draws them from this table. Edit both together.
const customIconPaths = <String, String>{
  'custom:persienn halvöppen':
      'M1.563 20.099H21.562V21.787H1.563ZM3.408 2.445H5.596V20.507H3.408ZM17.288 2.445H19.475V20.507H17.288ZM3.438 2.362H19.437V4.612H3.438ZM3.438 4.79H19.437V6.29H3.438ZM3.375 8.128H19.375V9.628H3.375ZM3.375 11.529H19.375V13.029H3.375ZM3.375 14.908H19.375V16.408H3.375ZM3.375 18.47H19.375V19.97H3.375Z',
  'custom:persienn stängd':
      'M1.563 20.099H21.562V21.787H1.563ZM3.408 2.445H5.596V20.507H3.408ZM17.288 2.445H19.475V20.507H17.288ZM3.438 2.362H19.437V4.612H3.438ZM3.438 4.79H19.437V6.29H3.438ZM3.375 6.481H19.375V7.981H3.375ZM3.375 8.128H19.375V9.628H3.375ZM3.375 9.829H19.375V11.329H3.375ZM3.375 11.529H19.375V13.029H3.375ZM3.375 13.22H19.375V14.72H3.375ZM3.375 14.908H19.375V16.408H3.375ZM3.375 16.658H19.375V18.158H3.375ZM3.375 18.47H19.375V19.97H3.375Z',
  'custom:persienn öppen mod':
      'M1.563 20.099H21.562V21.787H1.563ZM3.408 2.445H5.596V20.507H3.408ZM17.288 2.445H19.475V20.507H17.288ZM3.438 2.362H19.437V4.612H3.438Z',
  'custom:persienn öppen':
      'M1.563 20.099H21.562V21.787H1.563ZM3.408 2.445H5.596V20.507H3.408ZM17.288 2.445H19.475V20.507H17.288ZM3.438 2.362H19.437V4.612H3.438Z',
};

/// SVG path data -> a Path, for the commands icon paths use: M L H V C Z,
/// absolute and relative. Anything else ends the path where it stands -
/// a partial icon beats an exception in a card.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvCcZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  var cmd = '';
  double x = 0, y = 0, sx = 0, sy = 0;
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        x = next() + (rel ? x : 0);
        y = next() + (rel ? y : 0);
        path.moveTo(x, y);
        sx = x;
        sy = y;
        // further pairs after a moveto are linetos
        cmd = rel ? 'l' : 'L';
      case 'L':
        x = next() + (rel ? x : 0);
        y = next() + (rel ? y : 0);
        path.lineTo(x, y);
      case 'H':
        x = next() + (rel ? x : 0);
        path.lineTo(x, y);
      case 'V':
        y = next() + (rel ? y : 0);
        path.lineTo(x, y);
      case 'C':
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        final x1 = next() + ox, y1 = next() + oy, x2 = next() + ox, y2 = next() + oy;
        x = next() + ox;
        y = next() + oy;
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'Z':
        path.close();
        x = sx;
        y = sy;
      default:
        return path;
    }
  }
  return path;
}

final _parsed = <String, Path>{};

/// The path for a custom: name, parsed once, or null if the table has none.
Path? customIconPath(String? name) {
  if (name == null) return null;
  final d = customIconPaths[name];
  if (d == null) return null;
  return _parsed[name] ??= parseSvgPath(d);
}

/// Draws a 24x24 icon path at [size], in [color].
class PathIcon extends StatelessWidget {
  const PathIcon(this.path, {super.key, required this.size, required this.color});
  final Path path;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _PathPainter(path, color));
}

class _PathPainter extends CustomPainter {
  _PathPainter(this.path, this.color);
  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.path != path || old.color != color;
}
