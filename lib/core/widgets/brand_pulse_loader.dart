import 'package:material_ui/material_ui.dart';

/// ECG trace that draws itself, then a pulse runs the line — MEDCAIN's spinner.
class BrandPulseLoader extends StatefulWidget {
  const BrandPulseLoader({
    super.key,
    this.color,
    this.width = 148,
    this.height = 36,
  });

  final Color? color;
  final double width;
  final double height;

  @override
  State<BrandPulseLoader> createState() => _BrandPulseLoaderState();
}

class _BrandPulseLoaderState extends State<BrandPulseLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Loading',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size(widget.width, widget.height),
            painter: _EcgPainter(t: _controller.value, color: color),
          );
        },
      ),
    );
  }
}

class _EcgPainter extends CustomPainter {
  const _EcgPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _ecgPath(size);
    final faint = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, faint);

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final head = (t * metric.length).clamp(0, metric.length);
    final tail = (head - metric.length * 0.38).clamp(0, metric.length);

    final trace = metric.extractPath(tail.toDouble(), head.toDouble());
    final strong = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(trace, strong);

    final tangent = metric.getTangentForOffset(head.toDouble());
    if (tangent != null) {
      canvas.drawCircle(tangent.position, 3.6, Paint()..color = color);
    }
  }

  Path _ecgPath(Size size) {
    final w = size.width;
    final h = size.height;
    final y = h * 0.58;
    return Path()
      ..moveTo(0, y)
      ..lineTo(w * 0.16, y)
      ..lineTo(w * 0.24, y - h * 0.08)
      ..lineTo(w * 0.30, y + h * 0.07)
      ..lineTo(w * 0.46, y - h * 0.42)
      ..lineTo(w * 0.56, y + h * 0.30)
      ..lineTo(w * 0.66, y - h * 0.06)
      ..lineTo(w * 0.76, y)
      ..lineTo(w, y);
  }

  @override
  bool shouldRepaint(covariant _EcgPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}
