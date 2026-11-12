import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/spacing.dart';
import '../../domain/palette_cell.dart';
import 'palette_legend.dart';
import 'question_palette.dart';

/// Full palette with legend. Tapping a cell pops the sheet and navigates.
class QuestionPaletteSheet extends StatelessWidget {
  const QuestionPaletteSheet({
    super.key,
    required this.cells,
    required this.currentIndex,
    required this.isTutorMode,
    required this.onSelect,
    this.sectionNumbers,
    this.isReachable,
    this.scrollController,
  });

  final List<PaletteCell> cells;
  final int currentIndex;
  final bool isTutorMode;
  final ValueChanged<int> onSelect;
  final List<int>? sectionNumbers;
  final bool Function(int index)? isReachable;
  final ScrollController? scrollController;

  /// Bottom sheet sized with [DraggableScrollableSheet] so a 180-question
  /// grand test still scrolls inside the palette.
  static Future<void> show({
    required BuildContext context,
    required List<PaletteCell> cells,
    required int currentIndex,
    required bool isTutorMode,
    required ValueChanged<int> onSelect,
    List<int>? sectionNumbers,
    bool Function(int index)? isReachable,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return QuestionPaletteSheet(
              cells: cells,
              currentIndex: currentIndex,
              isTutorMode: isTutorMode,
              sectionNumbers: sectionNumbers,
              isReachable: isReachable,
              scrollController: scrollController,
              onSelect: (index) {
                Navigator.of(sheetContext).pop();
                onSelect(index);
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Column(
        children: [
          const SizedBox(height: Spacing.sm),
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(Spacing.xs),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Question Palette',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: PaletteLegend(isTutorMode: isTutorMode),
          ),
          const SizedBox(height: Spacing.md),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                QuestionPalette(
                  cells: cells,
                  currentIndex: currentIndex,
                  sectionNumbers: sectionNumbers,
                  isReachable: isReachable,
                  onSelect: onSelect,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
