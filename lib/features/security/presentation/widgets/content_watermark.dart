import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Faint repeating identity overlay. Visual only — does not block input.
class ContentWatermark extends StatelessWidget {
  const ContentWatermark({super.key, required this.text});

  final String text;

  /// Dense enough to survive a crop, light enough to keep stems readable.
  static const double opacity = 0.12;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final color = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: opacity);

    // IgnorePointer: paint on top of the player without stealing option taps.
    // ExcludeSemantics: don't let TalkBack read the same string dozens of times.
    return IgnorePointer(
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _TiledWatermarkPainter(text: text, color: color),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TiledWatermarkPainter extends CustomPainter {
  _TiledWatermarkPainter({required this.text, required this.color});

  final String text;
  final Color color;

  static const double _fontSize = 12;
  static const double _gapX = 56;
  static const double _gapY = 80;
  static const double _angle = -math.pi / 6;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: _fontSize,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final stepX = painter.width + _gapX;
    final stepY = painter.height + _gapY;
    if (stepX <= 0 || stepY <= 0) {
      painter.dispose();
      return;
    }
    // Cover corners after rotation — the axis-aligned box isn't enough.
    final bound = size.longestSide;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(_angle);

    for (var y = -bound; y < bound; y += stepY) {
      for (var x = -bound; x < bound; x += stepX) {
        painter.paint(canvas, Offset(x, y));
      }
    }

    canvas.restore();
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _TiledWatermarkPainter oldDelegate) {
    return oldDelegate.text != text || oldDelegate.color != color;
  }
}
