import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../../domain/paper_outline.dart';
import '../../domain/pyq_models.dart';
import '../../domain/pyq_sections.dart';
import '../open_pyq_reader.dart';
import '../providers/pyq_providers.dart';
import '../widgets/pyq_teaser_card.dart';

/// One exam year and, when [paperName] is set, one printed paper
/// (Paper I, Paper II, …): pinned LAQ / Short notes / MCQ / Other tabs.
class YearPaperOutlineScreen extends ConsumerWidget {
  const YearPaperOutlineScreen({
    super.key,
    required this.subjectId,
    required this.year,
    required this.title,
    this.universityId,
    this.section,
    this.collegeId,
    this.paperName,
  });

  final String subjectId;
  final int year;
  final String title;

  /// Which row on the subject screen was tapped. Both null shows every
  /// sitting in [year].
  final String? universityId;

  /// A [PyqSection] name.
  final String? section;

  /// Campus-paper rows also pass the college so another campus's stems stay out.
  final String? collegeId;

  /// Printed paper (`Paper I`). Null keeps every paper in the year. Empty
  /// string means the sheet left the paper label blank.
  final String? paperName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subjectPyqsProvider(subjectId));
    final filter = ref.watch(subjectPyqFiltersProvider(subjectId));
    final profile = ref.watch(userProfileProvider).value;
    final scopeSection = PyqSection.values.asNameMap()[section];
    final scopeUniversityId = universityId;
    // Null = no college filter. Empty string = papers with no college set.
    final scopeCollegeId = collegeId;
    final paperTitle = _paperTitle(paperName);
    // Narrow to the tapped row so a KUHS 2024 Paper I row does not also list
    // Paper II, or the 2024 stems of another university (or another campus).
    final bool Function(PaperSitting)? scope =
        (scopeSection == null || scopeUniversityId == null) && paperName == null
        ? null
        : (sitting) {
            if (scopeSection != null && scopeUniversityId != null) {
              if (sitting.universityId != scopeUniversityId) return false;
              if (classifySitting(
                    sitting,
                    userUniversityId: profile?.universityId,
                  ) !=
                  scopeSection) {
                return false;
              }
              if (scopeCollegeId != null) {
                if (scopeCollegeId.isEmpty) {
                  if (sitting.collegeId != null) return false;
                } else if (sitting.collegeId != scopeCollegeId) {
                  return false;
                }
              }
            }
            if (paperName == null) return true;
            return (sitting.paperName?.trim() ?? '') == paperName!.trim();
          };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          paperTitle == null
              ? '$title · $year'
              : '$title · $year · $paperTitle',
        ),
      ),
      body: async.when(
        loading: () => const AsyncLoadingView(),
        error: (e, _) => AsyncErrorView(
          message: UserFacingError.display(e),
          onAction: () => ref.invalidate(subjectPyqsProvider(subjectId)),
        ),
        data: (feed) {
          List<PyqTeaser> forTab(PaperOutlineTab tab) => teasersForOutlineTab(
            teasers: feed.teasers,
            year: year,
            tab: tab,
            paperName: filter.paperName,
            universityId: filter.universityId,
            examType: filter.examType,
            isMcq: filter.isMcq,
            sittingScope: scope,
            topicId: filter.topicId,
            priorities: filter.priorities,
          );
          return _OutlineBody(
            year: year,
            paperLabel: paperTitle,
            longAnswer: forTab(PaperOutlineTab.longAnswer),
            shortNotes: forTab(PaperOutlineTab.shortNotes),
            mcq: forTab(PaperOutlineTab.mcq),
            other: forTab(PaperOutlineTab.other),
          );
        },
      ),
    );
  }
}

/// Null when the route did not pick a paper. Empty sheet labels read "Paper".
String? _paperTitle(String? paperName) {
  if (paperName == null) return null;
  final trimmed = paperName.trim();
  return trimmed.isEmpty ? 'Paper' : trimmed;
}

class _OutlineBody extends StatefulWidget {
  const _OutlineBody({
    required this.year,
    this.paperLabel,
    required this.longAnswer,
    required this.shortNotes,
    required this.mcq,
    required this.other,
  });

  final int year;
  final String? paperLabel;
  final List<PyqTeaser> longAnswer;
  final List<PyqTeaser> shortNotes;
  final List<PyqTeaser> mcq;
  final List<PyqTeaser> other;

  @override
  State<_OutlineBody> createState() => _OutlineBodyState();
}

class _OutlineBodyState extends State<_OutlineBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: PaperOutlineTab.values.length,
      vsync: this,
      initialIndex: defaultPaperOutlineTabIndex(
        longAnswer: widget.longAnswer,
        shortNotes: widget.shortNotes,
        mcq: widget.mcq,
        other: widget.other,
      ),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<PyqTeaser> _listFor(PaperOutlineTab tab) => switch (tab) {
    PaperOutlineTab.longAnswer => widget.longAnswer,
    PaperOutlineTab.shortNotes => widget.shortNotes,
    PaperOutlineTab.mcq => widget.mcq,
    PaperOutlineTab.other => widget.other,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final tab in PaperOutlineTab.values)
              // No separator between label and count: four tabs already only
              // just fit a 360dp screen, and ' · ' pushed MCQ off-screen.
              Tab(text: '${tab.label} ${_listFor(tab).length}'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              for (final tab in PaperOutlineTab.values)
                _OutlineQuestionList(
                  year: widget.year,
                  paperLabel: widget.paperLabel,
                  tab: tab,
                  teasers: _listFor(tab),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutlineQuestionList extends StatelessWidget {
  const _OutlineQuestionList({
    required this.year,
    this.paperLabel,
    required this.tab,
    required this.teasers,
  });

  final int year;
  final String? paperLabel;
  final PaperOutlineTab tab;
  final List<PyqTeaser> teasers;

  @override
  Widget build(BuildContext context) {
    if (teasers.isEmpty) {
      return AsyncEmptyView(
        icon: Icons.description_outlined,
        message: tab.emptyMessage(year, paperLabel),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.md),
      itemCount: teasers.length,
      itemBuilder: (context, i) {
        final teaser = teasers[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: PyqTeaserCard(
            teaser: teaser,
            index: i,
            onTap: () => openPyqReader(
              context,
              questionId: teaser.id,
              questionIds: [for (final item in teasers) item.id],
            ),
          ),
        );
      },
    );
  }
}
