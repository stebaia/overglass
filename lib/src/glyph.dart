import 'package:flutter/widgets.dart';

/// Shapes drawn by hand, so the package needs no icon font.
enum OverglassGlyph { add, close, back }

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.glyph, {super.key, required this.color, this.size = 24});

  final OverglassGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GlyphPainter(glyph, color));
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);

  final OverglassGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width / 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final s = size.width;
    final path = switch (glyph) {
      OverglassGlyph.add =>
        Path()
          ..moveTo(s * .5, s * .2)
          ..lineTo(s * .5, s * .8)
          ..moveTo(s * .2, s * .5)
          ..lineTo(s * .8, s * .5),
      OverglassGlyph.close =>
        Path()
          ..moveTo(s * .25, s * .25)
          ..lineTo(s * .75, s * .75)
          ..moveTo(s * .75, s * .25)
          ..lineTo(s * .25, s * .75),
      OverglassGlyph.back =>
        Path()
          ..moveTo(s * .62, s * .2)
          ..lineTo(s * .32, s * .5)
          ..lineTo(s * .62, s * .8),
    };
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}
