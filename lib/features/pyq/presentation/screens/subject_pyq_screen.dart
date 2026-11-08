import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/navy_story.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/navy_story_widgets.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../practice/domain/practice_enums.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../../domain/pyq_sections.dart';
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

    final brightness = Theme.of(context).brightness;

    return Scaffold(
      backgroundColor: NavyStory.sheet(brightness),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(gradient: NavyStory.sky(brightness)),
        ),
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
                  if (filter.isMcq != null) filter.isMcq! ? 'MCQ' : 'Theory',
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
              // Empty string means the sheet left the paper label blank.
              paperName: group.paperName ?? '',
            ),
          );

          List<Widget> paperRows(List<PyqSittingGroup> groups) {
            return [
              for (var i = 0; i < groups.length; i++)
                _PaperCard(
                  group: groups[i],
                  last: i == groups.length - 1,
                  tone: i.isEven ? NavyStory.railStart : NavyStory.railEnd,
                  onTap: () => open(groups[i]),
                ),
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
                    _PaperCard(
                      group: sections.ownCollege[i],
                      last: i == sections.ownCollege.length - 1,
                      tone: i.isEven ? NavyStory.railStart : NavyStory.railEnd,
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
                    _PaperCard(
                      group: sections.other[i],
                      last: i == sections.other.length - 1,
                      tone: i.isEven ? NavyStory.railStart : NavyStory.railEnd,
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

/// One paper on the timeline. The year stays in the title because the
/// separate year heading would break the rail.
class _PaperCard extends StatelessWidget {
  const _PaperCard({
    required this.group,
    required this.onTap,
    required this.tone,
    required this.last,
  });

  final PyqSittingGroup group;
  final VoidCallback onTap;
  final Color tone;
  final bool last;

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

    return TimelineTile(
      key: ValueKey(
        '${group.section.name}-${group.year}-${group.paperLabel}-'
        '${group.collegeId ?? group.universityId}',
      ),
      tone: tone,
      last: last,
      onTap: onTap,
      semanticLabel: '${group.year} ${group.paperLabel}, $caption',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${group.year} ${group.paperLabel}',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
    );
  }
}
