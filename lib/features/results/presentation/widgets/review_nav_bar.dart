import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/spacing.dart';
import '../../../tests/presentation/widgets/palette_cell_view.dart';
import '../../domain/attempt_review.dart';

/// Horizontal jump bar. Locked questions stay tappable so the placeholder
/// can explain the plan gate instead of crashing.
class ReviewPaletteBar extends StatelessWidget {
  const ReviewPaletteBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<ReviewItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: Spacing.sm),
        itemBuilder: (context, index) {
          return PaletteCellView(
            cell: items[index].paletteCell,
            selected: index == currentIndex,
            onTap: () => onSelect(index),
          );
        },
      ),
    );
  }
}

class ReviewNavBar extends StatelessWidget {
  const ReviewNavBar({
    super.key,
    required this.currentIndex,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentIndex;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.md,
          Spacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onPrevious,
                child: const Text('Previous'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Text(
                '${currentIndex + 1} of $total',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Expanded(
              child: FilledButton(onPressed: onNext, child: const Text('Next')),
            ),
          ],
        ),
      ),
    );
  }
}
