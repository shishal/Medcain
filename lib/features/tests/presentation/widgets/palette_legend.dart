import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/theme/player_colors.dart';

/// Explains palette colors. Exam Mode matches the NEET convention in the
/// test-engine spec; Tutor Mode matches the practice spec.
class PaletteLegend extends StatelessWidget {
  const PaletteLegend({super.key, required this.isTutorMode});

  final bool isTutorMode;

  @override
  Widget build(BuildContext context) {
    final items = isTutorMode ? _tutorItems : _examItems;
    return Wrap(
      spacing: Spacing.md,
      runSpacing: Spacing.sm,
      children: [for (final item in items) _LegendItem(item: item)],
    );
  }

  static const _examItems = [
    _LegendSpec(label: 'Not Visited', fill: PlayerColors.notVisited),
    _LegendSpec(label: 'Not Answered', fill: PlayerColors.incorrect),
    _LegendSpec(label: 'Answered', fill: PlayerColors.correct),
    _LegendSpec(label: 'Marked for Review', fill: PlayerColors.review),
    _LegendSpec(
      label: 'Answered & Marked',
      fill: PlayerColors.review,
      showGreenCheck: true,
    ),
  ];

  static const _tutorItems = [
    _LegendSpec(label: 'Not Visited', fill: PlayerColors.notVisited),
    _LegendSpec(label: 'Skipped', outline: PlayerColors.incorrect),
    _LegendSpec(label: 'Correct', fill: PlayerColors.correct),
    _LegendSpec(label: 'Incorrect', fill: PlayerColors.incorrect),
    _LegendSpec(
      label: 'Marked for Review',
      fill: PlayerColors.notVisited,
      showReviewDot: true,
    ),
  ];
}

class _LegendSpec {
  const _LegendSpec({
    required this.label,
    this.fill,
    this.outline,
    this.showGreenCheck = false,
    this.showReviewDot = false,
  });

  final String label;
  final Color? fill;
  final Color? outline;
  final bool showGreenCheck;
  final bool showReviewDot;
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.item});

  final _LegendSpec item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: item.fill,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        item.outline ??
                        (item.fill == null
                            ? colorScheme.outline
                            : Colors.transparent),
                    width: item.outline != null ? 2 : 1,
                  ),
                ),
              ),
              if (item.showGreenCheck)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: PlayerColors.correct,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 7,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (item.showReviewDot)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: PlayerColors.review,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: Spacing.xs),
        Text(item.label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
