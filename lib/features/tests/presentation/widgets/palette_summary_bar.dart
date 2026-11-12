import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/spacing.dart';
import '../../domain/palette_cell.dart';
import '../../../../core/theme/player_colors.dart';

/// Compact counts + a button that opens the full question palette.
class PaletteSummaryBar extends StatelessWidget {
  const PaletteSummaryBar({
    super.key,
    required this.tally,
    required this.isTutorMode,
    required this.currentIndex,
    required this.total,
    required this.onOpenPalette,
  });

  final PaletteTally tally;
  final bool isTutorMode;
  final int currentIndex;
  final int total;
  final VoidCallback onOpenPalette;

  @override
  Widget build(BuildContext context) {
    final chips = isTutorMode
        ? [
            (tally.notVisited, PlayerColors.notVisited, 'Not visited'),
            (tally.notAnswered, PlayerColors.incorrect, 'Skipped'),
            (tally.correct, PlayerColors.correct, 'Correct'),
            (tally.incorrect, PlayerColors.incorrect, 'Incorrect'),
            (tally.marked, PlayerColors.review, 'Marked'),
          ]
        : [
            (tally.notVisited, PlayerColors.notVisited, 'Not visited'),
            (tally.notAnswered, PlayerColors.incorrect, 'Not answered'),
            (tally.answered, PlayerColors.correct, 'Answered'),
            (tally.marked, PlayerColors.review, 'Marked'),
          ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Question ${currentIndex + 1} of $total',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              TextButton.icon(
                key: const Key('question-palette-button'),
                onPressed: onOpenPalette,
                icon: const Icon(Icons.apps, size: 18),
                label: const Text('Question Palette'),
              ),
            ],
          ),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              for (final chip in chips)
                _CountChip(count: chip.$1, color: chip.$2, label: chip.$3),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.count,
    required this.color,
    required this.label,
  });

  final int count;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Spacing.xs),
          Text('$count $label', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
