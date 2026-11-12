import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/spacing.dart';
import '../../domain/palette_cell.dart';
import 'palette_cell_view.dart';

/// Numbered palette grid. Tapping a cell jumps to that question.
class QuestionPalette extends StatelessWidget {
  const QuestionPalette({
    super.key,
    required this.cells,
    required this.currentIndex,
    required this.onSelect,
    this.sectionNumbers,
    this.isReachable,
  });

  final List<PaletteCell> cells;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// Parallel to [cells]. When more than one section is present, a header
  /// is shown per group (so Phase 5.3 can lock a section without a rewrite).
  final List<int>? sectionNumbers;

  /// When false, the cell is visible but not tappable (locked section).
  final bool Function(int index)? isReachable;

  @override
  Widget build(BuildContext context) {
    final sections = _groups();
    final showHeaders = sections.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in sections) ...[
          if (showHeaders) ...[
            Text(
              'Section ${group.section}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Spacing.sm),
          ],
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final index in group.indices)
                PaletteCellView(
                  cell: cells[index],
                  selected: index == currentIndex,
                  locked: isReachable != null && !isReachable!(index),
                  onTap: () => onSelect(index),
                ),
            ],
          ),
          if (showHeaders) const SizedBox(height: Spacing.md),
        ],
      ],
    );
  }

  List<({int section, List<int> indices})> _groups() {
    final numbers = sectionNumbers;
    if (numbers == null || numbers.length != cells.length) {
      return [
        (section: 1, indices: [for (var i = 0; i < cells.length; i++) i]),
      ];
    }

    final groups = <({int section, List<int> indices})>[];
    for (var i = 0; i < numbers.length; i++) {
      final section = numbers[i];
      if (groups.isEmpty || groups.last.section != section) {
        groups.add((section: section, indices: [i]));
      } else {
        groups.last.indices.add(i);
      }
    }
    return groups;
  }
}
