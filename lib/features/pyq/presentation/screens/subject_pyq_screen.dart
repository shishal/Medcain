import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/comic_colors.dart';
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

/// How many year blocks stay visible before "Show earlier years".
const _visibleYearLimit = 3;

/// Third section accent. Blue and indigo are the brand pair; teal keeps
/// "other universities" distinct without using the Pro gold.
const _otherAccentLight = Color(0xFF0F766E);
const _otherAccentDark = Color(0xFF5EEAD4);

/// Subject → papers in three sections (own university, campus papers of that
/// university with the student's college first, then other universities).
/// Newest year first, then Paper I / Paper II under that year. Opening a
/// paper shows only that paper's questions.
///
/// The three blocks start closed so the page is a short list of choices.
/// Each block shows its three newest years until the student asks for more.
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
              // Always scope the month so August Paper I does not also
              // open October Paper I. Null month means the sheet had none.
              month: group.month,
              scopeMonth: true,
            ),
          );

          final emptyCopy = filter.isActive
              ? 'No papers match these filters.'
              : 'No papers yet.';

          final dark = Theme.of(context).brightness == Brightness.dark;
          final scheme = Theme.of(context).colorScheme;
          final accents = (
            own: scheme.primary,
            campus: ComicColors.of(context).accentPurple,
            other: dark ? _otherAccentDark : _otherAccentLight,
          );
          // Closed until opened, so the three blocks fit on one screen.
          // A filter opens any block that still has papers.
          bool openWhenFiltered(List<PyqSittingGroup> groups) =>
              filter.isActive && groups.isNotEmpty;

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
                  'Open a section, then a year. A paper mixes chapters.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
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
                const SizedBox(height: Spacing.md),
                // All three headings stay visible even when empty so the
                // layout (prof/supply, campus, other) never disappears.
                _CollapsibleSection(
                  key: ValueKey('own-${filter.isActive}'),
                  title: userUniversityId == null
                      ? 'Your university previous year questions'
                      : '${codeOf(userUniversityId)} previous year questions',
                  subtitle: _sectionSummary(sections.ownUniversity, emptyCopy),
                  icon: Icons.account_balance_rounded,
                  accent: accents.own,
                  initiallyExpanded: openWhenFiltered(sections.ownUniversity),
                  children: [
                    if (sections.ownUniversity.isNotEmpty)
                      _YearList(
                        key: const ValueKey('own-years'),
                        groups: sections.ownUniversity,
                        onOpen: open,
                      ),
                  ],
                ),
                _CollapsibleSection(
                  key: ValueKey('campus-${filter.isActive}'),
                  title: userUniversityId == null
                      ? 'Internal / pre-prof'
                      : '${codeOf(userUniversityId)} internal / pre-prof',
                  subtitle: _sectionSummary(
                    sections.ownCollege,
                    emptyCopy,
                    groupCount: _distinctCount(
                      sections.ownCollege,
                      (g) => g.collegeId ?? '',
                    ),
                    singular: 'college',
                    plural: 'colleges',
                  ),
                  icon: Icons.apartment_rounded,
                  accent: accents.campus,
                  initiallyExpanded: openWhenFiltered(sections.ownCollege),
                  children: [
                    if (sections.ownCollege.isNotEmpty)
                      for (final slice in _slices(
                        sections.ownCollege,
                        (g) => g.collegeId ?? '',
                        (g) => collegeLabelOf(g.collegeId),
                      )) ...[
                        _GroupHeading(slice.label, first: slice.first),
                        _YearList(
                          key: ValueKey('campus-${slice.id}'),
                          groups: slice.groups,
                          onOpen: open,
                        ),
                      ],
                  ],
                ),
                _CollapsibleSection(
                  key: ValueKey('other-${filter.isActive}'),
                  title: 'Other universities',
                  subtitle: _sectionSummary(
                    sections.other,
                    emptyCopy,
                    groupCount: _distinctCount(
                      sections.other,
                      (g) => g.universityId,
                    ),
                    singular: 'university',
                    plural: 'universities',
                  ),
                  icon: Icons.public_rounded,
                  accent: accents.other,
                  initiallyExpanded: openWhenFiltered(sections.other),
                  children: [
                    if (sections.other.isNotEmpty)
                      for (final slice in _slices(
                        sections.other,
                        (g) => g.universityId,
                        (g) => codeOf(g.universityId),
                      )) ...[
                        _GroupHeading(
                          slice.label,
                          first: slice.first,
                          accent: accents.other,
                        ),
                        _YearList(
                          key: ValueKey('other-${slice.id}'),
                          groups: slice.groups,
                          onOpen: open,
                        ),
                      ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// "4 papers · 2022–2025", or with a group count "2 colleges · 4 papers · …".
String _sectionSummary(
  List<PyqSittingGroup> groups,
  String emptyCopy, {
  int? groupCount,
  String? singular,
  String? plural,
}) {
  if (groups.isEmpty) return emptyCopy;
  var newest = groups.first.year;
  var oldest = groups.first.year;
  for (final group in groups) {
    if (group.year > newest) newest = group.year;
    if (group.year < oldest) oldest = group.year;
  }
  final span = newest == oldest ? '$newest' : '$oldest–$newest';
  final papers = groups.length == 1 ? '1 paper' : '${groups.length} papers';
  if (groupCount == null ||
      singular == null ||
      plural == null ||
      groupCount == 0) {
    return '$papers · $span';
  }
  final groupsLabel = groupCount == 1 ? '1 $singular' : '$groupCount $plural';
  return '$groupsLabel · $papers · $span';
}

int _distinctCount(
  List<PyqSittingGroup> groups,
  String Function(PyqSittingGroup group) idOf,
) {
  return groups.map(idOf).toSet().length;
}

class _GroupSlice {
  _GroupSlice(this.id, this.label, {required this.first});

  final String id;
  final String label;
  final bool first;
  final groups = <PyqSittingGroup>[];
}

/// Splits an already-ordered list into consecutive runs of [idOf].
List<_GroupSlice> _slices(
  List<PyqSittingGroup> groups,
  String Function(PyqSittingGroup group) idOf,
  String Function(PyqSittingGroup group) labelOf,
) {
  final slices = <_GroupSlice>[];
  for (final group in groups) {
    final id = idOf(group);
    if (slices.isEmpty || slices.last.id != id) {
      slices.add(
        _GroupSlice(id, labelOf(group), first: slices.isEmpty)
          ..groups.add(group),
      );
    } else {
      slices.last.groups.add(group);
    }
  }
  return slices;
}

/// One of the three blocks. State remembers open/closed across rebuilds
/// (a new filter result, a pull-to-refresh) without a provider.
class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.initiallyExpanded,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final comic = ComicColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent;
    final radius = BorderRadius.circular(AppTheme.cardRadius);
    // An empty block already explains itself in the subtitle, so it is not
    // a control that opens onto nothing.
    final canExpand = widget.children.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Material(
        color: comic.sticker,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: accent.withValues(alpha: dark ? 0.55 : 0.40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: canExpand,
              expanded: canExpand ? _expanded : null,
              label: '${widget.title}. ${widget.subtitle}',
              child: InkWell(
                onTap: canExpand
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
                child: Ink(
                  color: accent.withValues(alpha: dark ? 0.18 : 0.10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.md,
                    ),
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(widget.icon, color: accent, size: 20),
                          ),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (canExpand)
                            Icon(
                              _expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: accent,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (canExpand)
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.sm,
                          Spacing.sm,
                          Spacing.sm,
                          Spacing.xs,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Divider(
                              height: 1,
                              thickness: 2,
                              color: accent.withValues(alpha: 0.45),
                            ),
                            const SizedBox(height: Spacing.sm),
                            ...widget.children,
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.text, {required this.first, this.accent});

  final String text;
  final bool first;

  /// Set for university codes so the short name reads as a label, not body text.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = this.accent;
    final label = Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: accent,
        letterSpacing: accent == null ? null : 0.6,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : Spacing.sm, bottom: Spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!first) Divider(height: Spacing.lg, color: scheme.outlineVariant),
          if (accent == null)
            label
          else
            Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: dark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: accent.withValues(alpha: dark ? 0.7 : 0.45),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xs,
                  ),
                  child: label,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Consecutive papers that share a year. [groups] is already newest-first.
List<List<PyqSittingGroup>> _yearBuckets(List<PyqSittingGroup> groups) {
  final buckets = <List<PyqSittingGroup>>[];
  for (final group in groups) {
    if (buckets.isEmpty || buckets.last.first.year != group.year) {
      buckets.add([group]);
    } else {
      buckets.last.add(group);
    }
  }
  return buckets;
}

/// Shows the newest [_visibleYearLimit] years, then a control for the rest.
class _YearList extends StatefulWidget {
  const _YearList({super.key, required this.groups, required this.onOpen});

  final List<PyqSittingGroup> groups;
  final void Function(PyqSittingGroup group) onOpen;

  @override
  State<_YearList> createState() => _YearListState();
}

class _YearListState extends State<_YearList> {
  var _showAll = false;

  @override
  Widget build(BuildContext context) {
    final buckets = _yearBuckets(widget.groups);
    final visible = _showAll
        ? buckets
        : buckets.take(_visibleYearLimit).toList();
    final hidden = buckets.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final bucket in visible) ...[
          _YearHeading(bucket.first.year),
          for (final group in bucket)
            _PaperCard(group: group, onTap: () => widget.onOpen(group)),
        ],
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: Text(
                hidden == 1
                    ? 'Show 1 earlier year'
                    : 'Show $hidden earlier years',
              ),
            ),
          ),
        if (_showAll && buckets.length > _visibleYearLimit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAll = false),
              child: const Text('Show less'),
            ),
          ),
      ],
    );
  }
}

class _YearHeading extends StatelessWidget {
  const _YearHeading(this.year);

  final int year;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs, bottom: Spacing.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.xs,
            ),
            child: Text(
              '$year',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

/// One month and paper under a year, such as August · Paper I.
/// Opening it lists only that sitting.
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
      padding: const EdgeInsets.only(bottom: Spacing.sm),
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
