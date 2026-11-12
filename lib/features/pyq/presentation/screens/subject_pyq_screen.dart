import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../practice/domain/practice_enums.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../../domain/pyq_models.dart';
import '../../domain/pyq_sections.dart';
import '../../domain/subject_pyq_filters.dart';
import '../providers/pyq_providers.dart';
import '../widgets/subject_pyq_filter_sheet.dart';

/// Subject → papers in three sections (own university, campus papers of that
/// university with the student's college first, then other universities).
/// Newest year first, then Paper I / Paper II under that year. Opening a
/// paper shows only that paper's questions.
class SubjectPyqScreen extends ConsumerWidget {
  const SubjectPyqScreen({
    super.key,
    required this.subjectId,
    required this.title,
  });

  final String subjectId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subjectPyqsProvider(subjectId));
    final filter = ref.watch(subjectPyqFiltersProvider(subjectId));
    final profile = ref.watch(userProfileProvider).value;
    final universities = ref.watch(universitiesProvider).value ?? const [];
    final userUniversityId = profile?.universityId;
    final colleges = userUniversityId == null
        ? const []
        : (ref.watch(collegesProvider(userUniversityId)).value ?? const []);

    final universityCodes = {for (final u in universities) u.id: u.code};
    final collegeLabels = {
      for (final c in colleges)
        c.id: c.shortForm.isEmpty ? c.name : c.shortForm,
    };
    String codeOf(String id) => universityCodes[id] ?? 'University';
    String collegeLabelOf(String? id) =>
        id == null ? 'Campus papers' : (collegeLabels[id] ?? 'College');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton.icon(
            onPressed: () => async.whenOrNull(
              data: (feed) => showSubjectPyqFilterSheet(
                context: context,
                subjectId: subjectId,
                teasers: feed.teasers,
                chapters: feed.chapters,
              ),
            ),
            icon: Icon(
              filter.isActive
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_outlined,
            ),
            label: const Text('Filters'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const AsyncLoadingView(),
        error: (e, _) => AsyncErrorView(
          message: UserFacingError.display(e),
          onAction: () => ref.invalidate(subjectPyqsProvider(subjectId)),
        ),
        data: (feed) {
          final sections = buildPyqSections(
            teasers: feed.teasers,
            filter: filter,
            userUniversityId: userUniversityId,
            userCollegeId: profile?.collegeId,
            universityCodes: universityCodes,
          );
          final activeSummary = filter.isActive
              ? [
                  if (filter.universityIds.isNotEmpty)
                    (filter.universityIds.map(codeOf).toList()..sort()).join(
                      ', ',
                    ),
                  if (filter.years.isNotEmpty)
                    (filter.years.toList()..sort((a, b) => b.compareTo(a)))
                        .join(', '),
                  if (filter.examTypes.isNotEmpty)
                    PaperExamType.values
                        .where(filter.examTypes.contains)
                        .map((type) => type.label)
                        .join(', '),
                  if (filter.paperNames.isNotEmpty)
                    (filter.paperNames.toList()..sort()).join(', '),
                  if (filter.questionKinds.isNotEmpty)
                    PyqQuestionKind.values
                        .where(filter.questionKinds.contains)
                        .map((kind) => kind.label)
                        .join(', '),
                  if (filter.topicIds.isNotEmpty)
                    feed.chapters
                        .where((c) => filter.topicIds.contains(c.id))
                        .map((c) => c.name)
                        .join(', '),
                  if (filter.priorities.isNotEmpty)
                    QuestionPriority.values
                        .where(filter.priorities.contains)
                        .map((p) => p.label)
                        .join(', '),
                ].where((part) => part.isNotEmpty).join(' · ')
              : null;

          void open(PyqSittingGroup group) => context.push(
            AppRoutes.subjectYearPath(
              subjectId,
              group.year,
              title,
              universityId: group.universityId,
              section: group.section.name,
              // Empty string means "no college on the paper" so the outline
              // does not mix in another campus of the same year.
              collegeId: group.section == PyqSection.ownCollege
                  ? (group.collegeId ?? '')
                  : null,
              // Empty string means the sheet left the paper label blank.
              paperName: group.paperName ?? '',
            ),
          );

          List<Widget> paperRows(List<PyqSittingGroup> groups) {
            return [
              for (var i = 0; i < groups.length; i++) ...[
                if (_startsPaperYear(groups, i)) _YearHeading(groups[i].year),
                _PaperCard(group: groups[i], onTap: () => open(groups[i])),
              ],
            ];
          }

          final emptyCopy = filter.isActive
              ? 'No papers match these filters.'
              : 'No papers yet.';

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(subjectPyqsProvider(subjectId)),
            child: ListView(
              // AlwaysScrollable so pull-to-refresh works when every
              // section is empty.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                Text(
                  'Previous year questions',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Pick a paper under a year. A university paper mixes chapters.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (activeSummary != null && activeSummary.isNotEmpty) ...[
                  const SizedBox(height: Spacing.sm),
                  Text(
                    activeSummary,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (filter.isActive && sections.isEmpty)
                    TextButton(
                      onPressed: ref
                          .read(subjectPyqFiltersProvider(subjectId).notifier)
                          .clear,
                      child: const Text('Clear filters'),
                    ),
                ],
                // Keep all three section headings visible even when empty so
                // students always see the layout (prof/supply, campus, other).
                _SectionHeader(
                  userUniversityId == null
                      ? 'Your university previous year questions'
                      : '${codeOf(userUniversityId)} previous year questions',
                ),
                if (sections.ownUniversity.isEmpty)
                  _EmptySection(emptyCopy)
                else
                  ...paperRows(sections.ownUniversity),
                _SectionHeader(
                  userUniversityId == null
                      ? 'Internal / pre-prof'
                      : '${codeOf(userUniversityId)} internal / pre-prof',
                ),
                if (sections.ownCollege.isEmpty)
                  _EmptySection(emptyCopy)
                else
                  for (var i = 0; i < sections.ownCollege.length; i++) ...[
                    // Own college first, then other campuses — one heading each.
                    if (i == 0 ||
                        sections.ownCollege[i].collegeId !=
                            sections.ownCollege[i - 1].collegeId)
                      _UniversityHeading(
                        collegeLabelOf(sections.ownCollege[i].collegeId),
                      ),
                    if (_startsPaperYear(sections.ownCollege, i))
                      _YearHeading(sections.ownCollege[i].year),
                    _PaperCard(
                      group: sections.ownCollege[i],
                      onTap: () => open(sections.ownCollege[i]),
                    ),
                  ],
                const _SectionHeader('Other universities'),
                if (sections.other.isEmpty)
                  _EmptySection(emptyCopy)
                else
                  for (var i = 0; i < sections.other.length; i++) ...[
                    // One small heading per university; the list is already
                    // grouped by university.
                    if (i == 0 ||
                        sections.other[i].universityId !=
                            sections.other[i - 1].universityId)
                      _UniversityHeading(
                        codeOf(sections.other[i].universityId),
                      ),
                    if (_startsPaperYear(sections.other, i))
                      _YearHeading(sections.other[i].year),
                    _PaperCard(
                      group: sections.other[i],
                      onTap: () => open(sections.other[i]),
                    ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.lg, bottom: Spacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _UniversityHeading extends StatelessWidget {
  const _UniversityHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs, bottom: Spacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// True when this row starts a new year block (or a new college / university).
bool _startsPaperYear(List<PyqSittingGroup> groups, int index) {
  if (index == 0) return true;
  final previous = groups[index - 1];
  final current = groups[index];
  return previous.year != current.year ||
      previous.universityId != current.universityId ||
      previous.collegeId != current.collegeId;
}

class _YearHeading extends StatelessWidget {
  const _YearHeading(this.year);

  final int year;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.xs),
      child: Text(
        '$year',
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Paper I / Paper II under a year. Opening it lists only that paper.
class _PaperCard extends StatelessWidget {
  const _PaperCard({required this.group, required this.onTap});

  final PyqSittingGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final count = group.questionCount;
    final caption = [
      count == 1 ? '1 question' : '$count questions',
      if (group.examTypes.isNotEmpty)
        group.examTypes.map((t) => t.label).join(' / '),
    ].join(' · ');

    return Padding(
      key: ValueKey(
        '${group.section.name}-${group.year}-${group.paperLabel}-'
        '${group.collegeId ?? group.universityId}',
      ),
      padding: const EdgeInsets.only(left: Spacing.md, bottom: Spacing.sm),
      child: ComicCard(
        onTap: onTap,
        semanticLabel: '${group.year} ${group.paperLabel}, $caption',
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.paperLabel,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: muted),
          ],
        ),
      ),
    );
  }
}
