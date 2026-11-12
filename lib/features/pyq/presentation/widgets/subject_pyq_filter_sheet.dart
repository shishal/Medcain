import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/spacing.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../practice/domain/practice_enums.dart';
import '../../domain/pyq_models.dart';
import '../../domain/subject_pyq_filters.dart';
import '../providers/pyq_providers.dart';

Future<void> showSubjectPyqFilterSheet({
  required BuildContext context,
  required String subjectId,
  required List<PyqTeaser> teasers,
  required List<PyqChapter> chapters,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return SubjectPyqFilterSheet(
        subjectId: subjectId,
        teasers: teasers,
        chapters: chapters,
      );
    },
  );
}

/// University > Year > Exam type > Paper > MCQ/Theory, then chapter and
/// priority. Each level only offers what exists under the picks above it.
/// Every row can combine several values; All clears that row.
class SubjectPyqFilterSheet extends ConsumerWidget {
  const SubjectPyqFilterSheet({
    super.key,
    required this.subjectId,
    required this.teasers,
    required this.chapters,
  });

  final String subjectId;
  final List<PyqTeaser> teasers;
  final List<PyqChapter> chapters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(subjectPyqFiltersProvider(subjectId));
    final notifier = ref.read(subjectPyqFiltersProvider(subjectId).notifier);
    final media = MediaQuery.of(context);
    final options = availableFilterOptions(teasers, filter);
    final universities = ref.watch(universitiesProvider).value ?? const [];
    final universityCodes = {for (final u in universities) u.id: u.code};

    // Cap height so the sheet never grows past the screen; chips scroll while
    // Clear/Done stay pinned at the bottom (otherwise Done falls off a phone
    // viewport once every chip group is shown).
    final maxHeight = media.size.height * 0.9;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Filters',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (options.universityIds.isNotEmpty)
                          _ChipGroup(
                            title: 'University',
                            allLabel: 'All universities',
                            isAllSelected: filter.universityIds.isEmpty,
                            onAll: notifier.clearUniversities,
                            chips: [
                              for (final id in options.universityIds)
                                _ChipData(
                                  label: universityCodes[id] ?? 'University',
                                  selected: filter.universityIds.contains(id),
                                  onSelected: () =>
                                      notifier.toggleUniversity(id),
                                ),
                            ],
                          ),
                        if (options.years.isNotEmpty)
                          _ChipGroup(
                            title: 'Year',
                            allLabel: 'All years',
                            isAllSelected: filter.years.isEmpty,
                            onAll: notifier.clearYears,
                            chips: [
                              for (final year in options.years)
                                _ChipData(
                                  label: '$year',
                                  selected: filter.years.contains(year),
                                  onSelected: () => notifier.toggleYear(year),
                                ),
                            ],
                          ),
                        if (options.examTypes.isNotEmpty)
                          _ChipGroup(
                            title: 'Exam type',
                            allLabel: 'All types',
                            isAllSelected: filter.examTypes.isEmpty,
                            onAll: notifier.clearExamTypes,
                            chips: [
                              for (final type in options.examTypes)
                                _ChipData(
                                  label: type.label,
                                  selected: filter.examTypes.contains(type),
                                  onSelected: () =>
                                      notifier.toggleExamType(type),
                                ),
                            ],
                          ),
                        if (options.paperNames.isNotEmpty)
                          _ChipGroup(
                            title: 'Paper',
                            allLabel: 'All papers',
                            isAllSelected: filter.paperNames.isEmpty,
                            onAll: notifier.clearPaperNames,
                            chips: [
                              for (final name in options.paperNames)
                                _ChipData(
                                  label: name,
                                  selected: filter.paperNames.contains(name),
                                  onSelected: () =>
                                      notifier.togglePaperName(name),
                                ),
                            ],
                          ),
                        _ChipGroup(
                          title: 'Question type',
                          allLabel: 'MCQ + Theory',
                          isAllSelected: filter.questionKinds.isEmpty,
                          onAll: notifier.clearQuestionKinds,
                          chips: [
                            for (final kind in PyqQuestionKind.values)
                              _ChipData(
                                label: kind.label,
                                selected: filter.questionKinds.contains(kind),
                                onSelected: () =>
                                    notifier.toggleQuestionKind(kind),
                              ),
                          ],
                        ),
                        if (chapters.isNotEmpty)
                          _ChipGroup(
                            title: 'Chapters',
                            allLabel: 'All chapters',
                            isAllSelected: filter.topicIds.isEmpty,
                            onAll: notifier.clearTopics,
                            chips: [
                              for (final chapter in chapters)
                                _ChipData(
                                  label: chapter.name,
                                  selected: filter.topicIds.contains(
                                    chapter.id,
                                  ),
                                  onSelected: () =>
                                      notifier.toggleTopic(chapter.id),
                                ),
                            ],
                          ),
                        const SizedBox(height: Spacing.md),
                        Text(
                          'Revision priority',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          filter.priorities.isEmpty
                              ? 'None chosen — all questions. Untagged questions count as Should.'
                              : 'Untagged questions count as Should.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.sm,
                          children: [
                            for (final priority in QuestionPriority.values)
                              FilterChip(
                                label: Text(priority.label),
                                selected: filter.priorities.contains(priority),
                                onSelected: (_) =>
                                    notifier.togglePriority(priority),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                Row(
                  children: [
                    TextButton(
                      onPressed: filter.isActive ? notifier.clear : null,
                      child: const Text('Clear all'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipData {
  const _ChipData({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
}

/// A titled row of filter chips. All clears the row; the other chips toggle
/// and stay on together.
class _ChipGroup extends StatelessWidget {
  const _ChipGroup({
    required this.title,
    required this.allLabel,
    required this.isAllSelected,
    required this.onAll,
    required this.chips,
  });

  final String title;
  final String allLabel;
  final bool isAllSelected;
  final VoidCallback onAll;
  final List<_ChipData> chips;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Spacing.md),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            FilterChip(
              label: Text(allLabel),
              selected: isAllSelected,
              onSelected: (_) => onAll(),
            ),
            for (final chip in chips)
              FilterChip(
                label: Text(chip.label),
                selected: chip.selected,
                onSelected: (_) => chip.onSelected(),
              ),
          ],
        ),
      ],
    );
  }
}
