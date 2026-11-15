import 'package:material_ui/material_ui.dart';

/// Fade + rise in, delayed by [index] so grids feel like stickers landing.
class StaggeredFade extends StatelessWidget {
  const StaggeredFade({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delayMs = (index * 55).clamp(0, 420);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          // Once the entrance completes (`t >= 1`), skip the `Opacity` compositing
          // layer and `Transform` completely so cards paint directly.
          child: t >= 1
              ? child
              : Transform.translate(
                  offset: Offset(0, 18 * (1 - t)),
                  child: child,
                ),
        );
      },
      child: child,
    );
  }
}
