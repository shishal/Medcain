import '../../practice/domain/practice_enums.dart';
import 'pyq_models.dart';
import 'question_format.dart';

/// MCQ vs written theory on the subject filter.
///
/// An empty set means both. Several values mean "any of these".
enum PyqQuestionKind {
  mcq,
  theory;

  String get label => switch (this) {
    PyqQuestionKind.mcq => 'MCQ',
    PyqQuestionKind.theory => 'Theory',
  };
}

/// Picks on the subject PYQ screen.
///
/// Each set is empty when that row is "All". A question is kept when one
/// sitting hits every non-empty sitting set (university, year, exam type,
/// paper), and the question's own tags hit chapter, question kind, and
/// priority. Within one set, any selected value is enough.
class SubjectPyqFilter {
  const SubjectPyqFilter({
    this.universityIds = const {},
    this.years = const {},
    this.examTypes = const {},
    this.paperNames = const {},
    this.questionKinds = const {},
    this.topicIds = const {},
    this.priorities = const {},
  });

  final Set<String> universityIds;
  final Set<int> years;
  final Set<PaperExamType> examTypes;
  final Set<String> paperNames;

  /// Empty = MCQ and theory.
  final Set<PyqQuestionKind> questionKinds;

  /// Empty = every chapter, including questions with no chapter tag.
  final Set<String> topicIds;

  /// Empty = every priority.
  final Set<QuestionPriority> priorities;

  bool get isActive =>
      universityIds.isNotEmpty ||
      years.isNotEmpty ||
      examTypes.isNotEmpty ||
      paperNames.isNotEmpty ||
      questionKinds.isNotEmpty ||
      topicIds.isNotEmpty ||
      priorities.isNotEmpty;

  SubjectPyqFilter copyWith({
    Set<String>? universityIds,
    Set<int>? years,
    Set<PaperExamType>? examTypes,
    Set<String>? paperNames,
    Set<PyqQuestionKind>? questionKinds,
    Set<String>? topicIds,
    Set<QuestionPriority>? priorities,
  }) {
    return SubjectPyqFilter(
      universityIds: universityIds ?? this.universityIds,
      years: years ?? this.years,
      examTypes: examTypes ?? this.examTypes,
      paperNames: paperNames ?? this.paperNames,
      questionKinds: questionKinds ?? this.questionKinds,
      topicIds: topicIds ?? this.topicIds,
      priorities: priorities ?? this.priorities,
    );
  }
}

/// True when [sitting] satisfies every sitting-level pick. All picks are
/// checked on the same sitting: "2023" and "Paper II" must be one paper,
/// not a 2023 Paper I plus a different year's Paper II.
///
/// An empty set does not narrow. A set with several values matches if the
/// sitting has any one of them.
bool sittingMatches(PaperSitting sitting, SubjectPyqFilter filter) {
  return _allows(filter.universityIds, sitting.universityId) &&
      _allows(filter.years, sitting.year) &&
      _allows(filter.examTypes, sitting.examType) &&
      _allows(filter.paperNames, sitting.label);
}

bool _allows<T>(Set<T> selected, T value) =>
    selected.isEmpty || selected.contains(value);

PyqQuestionKind _questionKind(PyqTeaser teaser) =>
    teaser.kind == 'mcq' ? PyqQuestionKind.mcq : PyqQuestionKind.theory;

/// Client-side chips on a subject PYQ feed. Does not score or gate plans.
///
/// [sittingScope] lets the year outline narrow to one section row, and
/// [year] to that row's year, on top of the picks.
List<PyqTeaser> filterSubjectPyqs({
  required List<PyqTeaser> teasers,
  QuestionFormat? format,
  Set<PyqQuestionKind> questionKinds = const {},
  Set<String> universityIds = const {},
  Set<PaperExamType> examTypes = const {},
  Set<String> paperNames = const {},
  Set<int> years = const {},
  int? year,
  bool Function(PaperSitting sitting)? sittingScope,
  Set<String> topicIds = const {},
  Set<QuestionPriority> priorities = const {},
}) {
  final sittingPicks = SubjectPyqFilter(
    universityIds: universityIds,
    years: years,
    examTypes: examTypes,
    paperNames: paperNames,
  );
  final needsSitting =
      universityIds.isNotEmpty ||
      examTypes.isNotEmpty ||
      paperNames.isNotEmpty ||
      years.isNotEmpty ||
      year != null ||
      sittingScope != null;

  bool sittingOk(PyqTeaser t) {
    if (!needsSitting) return true;
    return t.sittings.any(
      (s) =>
          sittingMatches(s, sittingPicks) &&
          (year == null || s.year == year) &&
          (sittingScope == null || sittingScope(s)),
    );
  }

  final out = [
    for (final t in teasers)
      if ((format == null || t.format == format) &&
          _allows(questionKinds, _questionKind(t)) &&
          sittingOk(t) &&
          (topicIds.isEmpty ||
              (t.topicId != null && topicIds.contains(t.topicId))) &&
          (priorities.isEmpty || priorities.contains(t.priority)))
        t,
  ];
  // A single printed paper in a single year: essays first, then short,
  // VSA, MCQ (printed order). Several years or papers keep feed order.
  final pinnedYear = year != null && !years.contains(year) ? 1 : 0;
  if (paperNames.length == 1 && years.length + pinnedYear == 1) {
    out.sort((a, b) {
      final byFormat = a.format.index.compareTo(b.format.index);
      if (byFormat != 0) return byFormat;
      return b.appearanceCount.compareTo(a.appearanceCount);
    });
  }
  return out;
}

/// Teasers that pass every pick in [filter].
List<PyqTeaser> applySubjectPyqFilter(
  List<PyqTeaser> teasers,
  SubjectPyqFilter filter,
) {
  return filterSubjectPyqs(
    teasers: teasers,
    universityIds: filter.universityIds,
    years: filter.years,
    examTypes: filter.examTypes,
    paperNames: filter.paperNames,
    questionKinds: filter.questionKinds,
    topicIds: filter.topicIds,
    priorities: filter.priorities,
  );
}

/// What each filter level can still offer, given the picks above it.
class PyqFilterOptions {
  const PyqFilterOptions({
    this.universityIds = const [],
    this.years = const [],
    this.examTypes = const [],
    this.paperNames = const [],
  });

  final List<String> universityIds;

  /// Newest first.
  final List<int> years;
  final List<PaperExamType> examTypes;
  final List<String> paperNames;
}

/// University > Year > exam type > Paper. Each list only holds values that
/// exist under the picks made above it, so the sheet never offers a dead end.
/// Several picks at one level keep a value when any of them still has it.
PyqFilterOptions availableFilterOptions(
  List<PyqTeaser> teasers,
  SubjectPyqFilter filter,
) {
  final sittings = [for (final t in teasers) ...t.sittings];

  final universityIds = {for (final s in sittings) s.universityId};

  final underUniversity = [
    for (final s in sittings)
      if (_allows(filter.universityIds, s.universityId)) s,
  ];
  final years = {for (final s in underUniversity) s.year};

  final underYear = [
    for (final s in underUniversity)
      if (_allows(filter.years, s.year)) s,
  ];
  final examTypes = {for (final s in underYear) s.examType};

  final underType = [
    for (final s in underYear)
      if (_allows(filter.examTypes, s.examType)) s,
  ];
  final paperNames = {
    for (final s in underType)
      if (s.paperName != null || s.month != null) s.label,
  };

  return PyqFilterOptions(
    universityIds: universityIds.toList()..sort(),
    years: years.toList()..sort((a, b) => b.compareTo(a)),
    examTypes: [
      for (final type in PaperExamType.values)
        if (examTypes.contains(type)) type,
    ],
    paperNames: paperNames.toList()..sort(),
  );
}

Set<T> _kept<T>(Set<T> picked, Iterable<T> allowed) {
  if (picked.isEmpty) return picked;
  final allow = allowed.toSet();
  return picked.where(allow.contains).toSet();
}

/// Drops any sitting-level pick that no longer exists under the picks above
/// it, so changing University does not leave a stale Year behind.
/// A value stays when it still exists under at least one remaining parent.
SubjectPyqFilter reconcileFilter(
  SubjectPyqFilter filter,
  List<PyqTeaser> teasers,
) {
  var next = SubjectPyqFilter(
    questionKinds: filter.questionKinds,
    topicIds: filter.topicIds,
    priorities: filter.priorities,
  );
  next = next.copyWith(
    universityIds: _kept(
      filter.universityIds,
      availableFilterOptions(teasers, next).universityIds,
    ),
  );
  next = next.copyWith(
    years: _kept(filter.years, availableFilterOptions(teasers, next).years),
  );
  next = next.copyWith(
    examTypes: _kept(
      filter.examTypes,
      availableFilterOptions(teasers, next).examTypes,
    ),
  );
  next = next.copyWith(
    paperNames: _kept(
      filter.paperNames,
      availableFilterOptions(teasers, next).paperNames,
    ),
  );
  return next;
}
