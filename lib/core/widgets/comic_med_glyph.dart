import 'package:material_ui/material_ui.dart';

import '../../features/catalog/domain/subject_visual.dart';
import '../theme/comic_colors.dart';

/// Thick-outline doodle of medical kit, drawn so it scales like a sticker.
class ComicMedGlyph extends StatelessWidget {
  const ComicMedGlyph({
    super.key,
    required this.glyph,
    this.size = 56,
    this.color,
  });

  final MedGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? ComicColors.of(context).ink;
    return CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(glyph: glyph, ink: ink),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({required this.glyph, required this.ink});

  final MedGlyph glyph;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = ink.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final c = Offset(size.width / 2, size.height / 2);
    final s = size.width;

    switch (glyph) {
      case MedGlyph.skull:
        final head = Rect.fromCenter(
          center: c.translate(0, -s * 0.04),
          width: s * 0.7,
          height: s * 0.72,
        );
        canvas.drawOval(head, fill);
        canvas.drawOval(head, stroke);
        canvas.drawCircle(c.translate(-s * 0.14, -s * 0.08), s * 0.08, stroke);
        canvas.drawCircle(c.translate(s * 0.14, -s * 0.08), s * 0.08, stroke);
      case MedGlyph.heart:
        final path = Path()
          ..moveTo(c.dx, c.dy + s * 0.28)
          ..cubicTo(
            c.dx - s * 0.45,
            c.dy,
            c.dx - s * 0.2,
            c.dy - s * 0.38,
            c.dx,
            c.dy - s * 0.08,
          )
          ..cubicTo(
            c.dx + s * 0.2,
            c.dy - s * 0.38,
            c.dx + s * 0.45,
            c.dy,
            c.dx,
            c.dy + s * 0.28,
          );
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
      case MedGlyph.flask:
        final path = Path()
          ..moveTo(c.dx - s * 0.12, c.dy - s * 0.32)
          ..lineTo(c.dx + s * 0.12, c.dy - s * 0.32)
          ..lineTo(c.dx + s * 0.12, c.dy - s * 0.04)
          ..lineTo(c.dx + s * 0.28, c.dy + s * 0.3)
          ..lineTo(c.dx - s * 0.28, c.dy + s * 0.3)
          ..lineTo(c.dx - s * 0.12, c.dy - s * 0.04)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
      case MedGlyph.microscope:
        canvas.drawCircle(c.translate(0, s * 0.18), s * 0.16, fill);
        canvas.drawCircle(c.translate(0, s * 0.18), s * 0.16, stroke);
        canvas.drawLine(
          c.translate(0, -s * 0.28),
          c.translate(0, s * 0.02),
          stroke,
        );
        canvas.drawLine(
          c.translate(-s * 0.22, s * 0.32),
          c.translate(s * 0.28, s * 0.32),
          stroke,
        );
      case MedGlyph.pills:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: c.translate(-s * 0.12, 0),
              width: s * 0.28,
              height: s * 0.5,
            ),
            Radius.circular(s * 0.14),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: c.translate(-s * 0.12, 0),
              width: s * 0.28,
              height: s * 0.5,
            ),
            Radius.circular(s * 0.14),
          ),
          stroke,
        );
        canvas.drawCircle(c.translate(s * 0.18, s * 0.04), s * 0.16, fill);
        canvas.drawCircle(c.translate(s * 0.18, s * 0.04), s * 0.16, stroke);
      case MedGlyph.bacteria:
        canvas.drawOval(
          Rect.fromCenter(center: c, width: s * 0.7, height: s * 0.5),
          fill,
        );
        canvas.drawOval(
          Rect.fromCenter(center: c, width: s * 0.7, height: s * 0.5),
          stroke,
        );
        canvas.drawCircle(c.translate(-s * 0.12, 0), s * 0.05, stroke);
        canvas.drawCircle(c.translate(s * 0.12, s * 0.04), s * 0.05, stroke);
      case MedGlyph.fingerprint:
        canvas.drawOval(
          Rect.fromCenter(center: c, width: s * 0.5, height: s * 0.66),
          stroke,
        );
        canvas.drawOval(
          Rect.fromCenter(center: c, width: s * 0.32, height: s * 0.46),
          stroke,
        );
      case MedGlyph.people:
        canvas.drawCircle(c.translate(-s * 0.16, -s * 0.12), s * 0.12, stroke);
        canvas.drawCircle(c.translate(s * 0.16, -s * 0.12), s * 0.12, stroke);
        canvas.drawArc(
          Rect.fromCenter(
            center: c.translate(-s * 0.16, s * 0.22),
            width: s * 0.36,
            height: s * 0.36,
          ),
          3.14,
          3.14,
          true,
          stroke,
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: c.translate(s * 0.16, s * 0.22),
            width: s * 0.36,
            height: s * 0.36,
          ),
          3.14,
          3.14,
          true,
          stroke,
        );
      case MedGlyph.ear:
        canvas.drawOval(
          Rect.fromCenter(center: c, width: s * 0.42, height: s * 0.7),
          fill,
        );
        canvas.drawOval(
          Rect.fromCenter(center: c, width: s * 0.42, height: s * 0.7),
          stroke,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: c.translate(s * 0.02, 0),
            width: s * 0.18,
            height: s * 0.32,
          ),
          stroke,
        );
      case MedGlyph.eye:
        final eye = Path()
          ..moveTo(c.dx - s * 0.36, c.dy)
          ..quadraticBezierTo(c.dx, c.dy - s * 0.28, c.dx + s * 0.36, c.dy)
          ..quadraticBezierTo(c.dx, c.dy + s * 0.28, c.dx - s * 0.36, c.dy);
        canvas.drawPath(eye, fill);
        canvas.drawPath(eye, stroke);
        canvas.drawCircle(c, s * 0.1, stroke);
      case MedGlyph.stethoscope:
        canvas.drawArc(
          Rect.fromCenter(
            center: c.translate(0, -s * 0.04),
            width: s * 0.55,
            height: s * 0.5,
          ),
          3.5,
          2.4,
          false,
          stroke,
        );
        canvas.drawCircle(c.translate(s * 0.22, s * 0.22), s * 0.12, fill);
        canvas.drawCircle(c.translate(s * 0.22, s * 0.22), s * 0.12, stroke);
      case MedGlyph.scalpel:
        canvas.drawLine(
          c.translate(-s * 0.28, s * 0.22),
          c.translate(s * 0.28, -s * 0.22),
          stroke,
        );
        canvas.drawCircle(c.translate(s * 0.28, -s * 0.22), s * 0.08, fill);
      case MedGlyph.baby:
        canvas.drawCircle(c.translate(0, -s * 0.08), s * 0.2, fill);
        canvas.drawCircle(c.translate(0, -s * 0.08), s * 0.2, stroke);
        canvas.drawOval(
          Rect.fromCenter(
            center: c.translate(0, s * 0.18),
            width: s * 0.5,
            height: s * 0.36,
          ),
          stroke,
        );
      case MedGlyph.bone:
        canvas.drawLine(
          c.translate(-s * 0.22, 0),
          c.translate(s * 0.22, 0),
          stroke,
        );
        canvas.drawCircle(c.translate(-s * 0.26, -s * 0.08), s * 0.1, stroke);
        canvas.drawCircle(c.translate(-s * 0.26, s * 0.08), s * 0.1, stroke);
        canvas.drawCircle(c.translate(s * 0.26, -s * 0.08), s * 0.1, stroke);
        canvas.drawCircle(c.translate(s * 0.26, s * 0.08), s * 0.1, stroke);
      case MedGlyph.brain:
        canvas.drawOval(
          Rect.fromCenter(center: c, width: s * 0.7, height: s * 0.55),
          fill,
        );
        canvas.drawOval(
          Rect.fromCenter(center: c, width: s * 0.7, height: s * 0.55),
          stroke,
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: c.translate(-s * 0.08, 0),
            width: s * 0.28,
            height: s * 0.28,
          ),
          0.4,
          2.4,
          false,
          stroke,
        );
      case MedGlyph.book:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: s * 0.62, height: s * 0.5),
            Radius.circular(s * 0.06),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: s * 0.62, height: s * 0.5),
            Radius.circular(s * 0.06),
          ),
          stroke,
        );
        canvas.drawLine(
          c.translate(0, -s * 0.22),
          c.translate(0, s * 0.22),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.ink != ink;
}
