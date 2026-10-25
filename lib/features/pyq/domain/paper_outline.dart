import 'pyq_models.dart';
import 'question_format.dart';
import 'subject_pyq_filters.dart';
import '../../practice/domain/practice_enums.dart';

/// Question-type tabs on a year's paper outline (Screen 3).
enum PaperOutlineTab {
  longAnswer,
  shortNotes,
  mcq,
  other;

  String get label => switch (this) {
    PaperOutlineTab.longAnswer => 'LAQ',
    PaperOutlineTab.shortNotes => 'Short notes',
    PaperOutlineTab.mcq => 'MCQ',
    PaperOutlineTab.other => 'Other',
  };

  String emptyMessage(int year) => switch (this) {
    PaperOutlineTab.longAnswer => 'No long answers in $year.',
    PaperOutlineTab.shortNotes => 'No short notes in $year.',
    PaperOutlineTab.mcq => 'No MCQs in $year.',
    PaperOutlineTab.other => 'No other questions in $year.',
  };
}

bool matchesOutlineTab(PyqTeaser teaser, PaperOutlineTab tab) {
  return switch (tab) {
    PaperOutlineTab.longAnswer => teaser.format == QuestionFormat.essay,
    PaperOutlineTab.shortNotes =>
      teaser.format == QuestionFormat.shortNote ||
          teaser.format == QuestionFormat.vsa,
    PaperOutlineTab.mcq => teaser.format == QuestionFormat.mcq,
    PaperOutlineTab.other => teaser.format == QuestionFormat.unclassified,
  };
}

/// Teasers for one year + tab, merged across Paper I / II.
List<PyqTeaser> teasersForOutlineTab({
  required List<PyqTeaser> teasers,
  required int year,
  required PaperOutlineTab tab,
  String? paperName,
  String? universityId,
  PaperExamType? examType,
  bool? isMcq,
  bool Function(PaperSitting sitting)? sittingScope,
  String? topicId,
  Set<QuestionPriority> priorities = const {},
}) {
  final filtered = filterSubjectPyqs(
    teasers: teasers,
    paperName: paperName,
    universityId: universityId,
    examType: examType,
    isMcq: isMcq,
    year: year,
    sittingScope: sittingScope,
    topicId: topicId,
    priorities: priorities,
  );
  final matching = [
    for (final t in filtered)
      if (matchesOutlineTab(t, tab)) t,
  ];
  matching.sort((a, b) {
    final byPaper = a.paperNames.join(',').compareTo(b.paperNames.join(','));
    if (byPaper != 0) return byPaper;
    return (b.marks ?? 0).compareTo(a.marks ?? 0);
  });
  return matching;
}

/// Long answer if that list is non-empty, otherwise the first tab with questions.
int defaultPaperOutlineTabIndex({
  required List<PyqTeaser> longAnswer,
  required List<PyqTeaser> shortNotes,
  required List<PyqTeaser> mcq,
  required List<PyqTeaser> other,
}) {
  if (longAnswer.isNotEmpty) return 0;
  if (shortNotes.isNotEmpty) return 1;
  if (mcq.isNotEmpty) return 2;
  if (other.isNotEmpty) return 3;
  return 0;
}
