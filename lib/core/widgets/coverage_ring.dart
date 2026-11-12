import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Circular stroke for a 0–1 fraction (lesson coverage, accuracy).
///
/// Pass a value the server already computed. Do not derive a new score here.
class CoverageRing extends StatelessWidget {
  const CoverageRing({
    super.key,
    required this.progress,
    this.size = 44,
    this.strokeWidth = 5,
    this.color,
    this.child,
  });

  final double progress;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = progress.clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: clamped,
          color: color ?? scheme.primary,
          track: scheme.outlineVariant.withValues(alpha: 0.55),
          strokeWidth: strokeWidth,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.track != track ||
      oldDelegate.strokeWidth != strokeWidth;
}
