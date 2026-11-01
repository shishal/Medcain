import 'package:flutter/material.dart';
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
import '../../domain/pyq_sections.dart';
import '../providers/pyq_providers.dart';
import '../widgets/subject_pyq_filter_sheet.dart';

/// Subject → papers in three sections (own university, campus papers of that
/// university with the student's college first, then other universities).
/// Newest year first. Filters carry into the year outline.
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
                  if (filter.universityId != null) codeOf(filter.universityId!),
                  if (filter.year != null) '${filter.year}',
                  if (filter.examType != null) filter.examType!.label,
                  if (filter.paperName != null) filter.paperName!,
                  if (filter.isMcq != null)
                    filter.isMcq! ? 'MCQ' : 'Theory',
                  if (filter.topicId != null)
                    feed.chapters
                        .where((c) => c.id == filter.topicId)
                        .map((c) => c.name)
                        .firstOrNull,
                  if (filter.priorities.isNotEmpty)
                    QuestionPriority.values
                        .where(filter.priorities.contains)
                        .map((p) => p.label)
                        .join(', '),
                ].whereType<String>().join(' · ')
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
            ),
          );

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
                  'Pick a year to see that sitting. A university paper mixes chapters.',
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
                  for (final group in sections.ownUniversity)
                    _YearCard(group: group, onTap: () => open(group)),
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
                    _YearCard(
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
                    _YearCard(
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
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A year row that says what opening it leads to, rather than just the number.
class _YearCard extends StatelessWidget {
  const _YearCard({required this.group, required this.onTap});

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
      if (group.paperNames.isNotEmpty) group.paperNames.join(' · '),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: ComicCard(
        onTap: onTap,
        semanticLabel: '${group.year}, $caption',
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${group.year}',
                    style: textTheme.titleLarge?.copyWith(
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
