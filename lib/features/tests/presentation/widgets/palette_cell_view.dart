import 'package:material_ui/material_ui.dart';

import '../../domain/palette_cell.dart';
import '../../../../core/theme/player_colors.dart';

/// One numbered palette cell. Visuals come from [PaletteCell] so Exam vs
/// Tutor rules stay out of this widget.
class PaletteCellView extends StatelessWidget {
  const PaletteCellView({
    super.key,
    required this.cell,
    required this.selected,
    required this.onTap,
    this.locked = false,
    this.size = 36,
  });

  final PaletteCell cell;
  final bool selected;
  final VoidCallback? onTap;
  final bool locked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fill = _fillColor(cell.fill);
    final outline = _outlineColor(cell.outline);
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      enabled: !locked,
      label: locked
          ? 'Question ${cell.questionNumber}, locked'
          : cell.semanticsLabel,
      excludeSemantics: true,
      child: InkWell(
        key: Key('palette-${cell.questionNumber}'),
        onTap: locked ? null : onTap,
        customBorder: const CircleBorder(),
        child: Opacity(
          opacity: locked ? 0.45 : 1,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? colorScheme.primary
                          : (outline ??
                                (fill == null
                                    ? colorScheme.outline
                                    : Colors.transparent)),
                      width: selected || outline != null ? 2.5 : 1,
                    ),
                  ),
                  child: Text(
                    '${cell.questionNumber}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: fill == null
                          ? colorScheme.onSurface
                          : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (cell.showGreenCheck)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: _CornerBadge(
                      color: PlayerColors.correct,
                      icon: Icons.check,
                      surface: colorScheme.surface,
                    ),
                  ),
                if (cell.showReviewDot)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: _CornerBadge(
                      color: PlayerColors.review,
                      surface: colorScheme.surface,
                    ),
                  ),
                if (locked)
                  Align(
                    child: Icon(
                      Icons.lock,
                      size: 12,
                      color: fill == null
                          ? colorScheme.onSurface
                          : Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color? _fillColor(PaletteFill fill) => switch (fill) {
    PaletteFill.grey => PlayerColors.notVisited,
    PaletteFill.red => PlayerColors.incorrect,
    PaletteFill.green => PlayerColors.correct,
    PaletteFill.purple => PlayerColors.review,
    PaletteFill.none => null,
  };

  static Color? _outlineColor(PaletteOutline outline) => switch (outline) {
    PaletteOutline.none => null,
    PaletteOutline.red => PlayerColors.incorrect,
    PaletteOutline.purple => PlayerColors.review,
  };
}

class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.color, required this.surface, this.icon});

  final Color color;
  final Color surface;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: surface, width: 1.5),
      ),
      child: icon == null ? null : Icon(icon, size: 8, color: Colors.white),
    );
  }
}
