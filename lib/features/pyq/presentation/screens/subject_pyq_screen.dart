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

/// Subject → papers in three sections (own university, own college, other
/// universities), newest year first. Filters carry into the year outline.
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
    String codeOf(String id) => universityCodes[id] ?? 'University';
    final ownCollege = colleges
        .where((c) => c.id == profile?.collegeId)
        .firstOrNull;

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

          if (sections.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(subjectPyqsProvider(subjectId)),
              child: ListView(
                // A scrollable is required for pull-to-refresh to have
                // somewhere to hang, even when the list itself is empty.
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: filter.isActive
                        ? AsyncEmptyView(
                            icon: Icons.filter_alt_off_outlined,
                            message: 'No papers match these filters.',
                            actionLabel: 'Clear filters',
                            onAction: ref
                                .read(
                                  subjectPyqFiltersProvider(subjectId).notifier,
                                )
                                .clear,
                          )
                        : AsyncEmptyView(
                            icon: Icons.history_edu_outlined,
                            message:
                                'No previous year papers for $title yet.\n'
                                'They arrive as your university is tagged.',
                          ),
                  ),
                ],
              ),
            );
          }

          void open(PyqSittingGroup group) => context.push(
            AppRoutes.subjectYearPath(
              subjectId,
              group.year,
              title,
              universityId: group.universityId,
              section: group.section.name,
            ),
          );

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(subjectPyqsProvider(subjectId)),
            child: ListView(
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
                ],
                if (sections.ownUniversity.isNotEmpty) ...[
                  _SectionHeader(
                    userUniversityId == null
                        ? 'Your university previous year questions'
                        : '${codeOf(userUniversityId)} previous year questions',
                  ),
                  for (final group in sections.ownUniversity)
                    _YearCard(group: group, onTap: () => open(group)),
                ],
                if (sections.ownCollege.isNotEmpty) ...[
                  _SectionHeader(
                    ownCollege == null || ownCollege.shortForm.isEmpty
                        ? 'Your college internal / pre-prof'
                        : '${ownCollege.shortForm} internal / pre-prof',
                  ),
                  for (final group in sections.ownCollege)
                    _YearCard(group: group, onTap: () => open(group)),
                ],
                if (sections.other.isNotEmpty) ...[
                  const _SectionHeader('Other universities'),
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
