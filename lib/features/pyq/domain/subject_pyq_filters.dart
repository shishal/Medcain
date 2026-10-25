import '../../practice/domain/practice_enums.dart';
import 'pyq_models.dart';
import 'question_format.dart';

// A private "not passed" marker. Dart cannot tell `copyWith(year: null)`
// (clear the year) from `copyWith()` (keep it) with a plain nullable
// parameter, so the defaults below use this object instead.
const Object _keep = Object();

/// Picks on the subject PYQ screen. The first five narrow *sittings*
/// (University > Year > exam type > Paper > MCQ/Theory); the rest are tags
/// on the question itself.
class SubjectPyqFilter {
  const SubjectPyqFilter({
    this.universityId,
    this.year,
    this.examType,
    this.paperName,
    this.isMcq,
    this.topicId,
    this.priorities = const {},
  });

  final String? universityId;
  final int? year;
  final PaperExamType? examType;
  final String? paperName;

  /// null = MCQ and theory, true = MCQ only, false = theory only.
  final bool? isMcq;
  final String? topicId;

  /// Empty = every priority.
  final Set<QuestionPriority> priorities;

  bool get isActive =>
      universityId != null ||
      year != null ||
      examType != null ||
      paperName != null ||
      isMcq != null ||
      topicId != null ||
      priorities.isNotEmpty;

  SubjectPyqFilter copyWith({
    Object? universityId = _keep,
    Object? year = _keep,
    Object? examType = _keep,
    Object? paperName = _keep,
    Object? isMcq = _keep,
    Object? topicId = _keep,
    Set<QuestionPriority>? priorities,
  }) {
    return SubjectPyqFilter(
      universityId: identical(universityId, _keep)
          ? this.universityId
          : universityId as String?,
      year: identical(year, _keep) ? this.year : year as int?,
      examType: identical(examType, _keep)
          ? this.examType
          : examType as PaperExamType?,
      paperName: identical(paperName, _keep)
          ? this.paperName
          : paperName as String?,
      isMcq: identical(isMcq, _keep) ? this.isMcq : isMcq as bool?,
      topicId: identical(topicId, _keep) ? this.topicId : topicId as String?,
      priorities: priorities ?? this.priorities,
    );
  }
}

/// True when [sitting] satisfies every sitting-level pick. All picks are
/// checked on the same sitting: "2023" and "Paper II" must be one paper,
/// not two different ones.
bool sittingMatches(PaperSitting sitting, SubjectPyqFilter filter) {
  return (filter.universityId == null ||
          sitting.universityId == filter.universityId) &&
      (filter.year == null || sitting.year == filter.year) &&
      (filter.examType == null || sitting.examType == filter.examType) &&
      (filter.paperName == null || sitting.label == filter.paperName);
}

/// Client-side chips on a subject PYQ feed. Does not score or gate plans.
///
/// [sittingScope] lets the year outline narrow to one section row, and
/// [year] to that row's year, on top of the picks.
List<PyqTeaser> filterSubjectPyqs({
  required List<PyqTeaser> teasers,
  QuestionFormat? format,
  bool? isMcq,
  String? universityId,
  PaperExamType? examType,
  String? paperName,
  int? year,
  bool Function(PaperSitting sitting)? sittingScope,
  String? topicId,
  Set<QuestionPriority> priorities = const {},
}) {
  final sittingPicks = SubjectPyqFilter(
    universityId: universityId,
    year: year,
    examType: examType,
    paperName: paperName,
  );
  final needsSitting =
      universityId != null ||
      examType != null ||
      paperName != null ||
      year != null ||
      sittingScope != null;

  bool sittingOk(PyqTeaser t) {
    if (!needsSitting) return true;
    return t.sittings.any(
      (s) =>
          sittingMatches(s, sittingPicks) &&
          (sittingScope == null || sittingScope(s)),
    );
  }

  final out = [
    for (final t in teasers)
      if ((format == null || t.format == format) &&
          (isMcq == null || (t.kind == 'mcq') == isMcq) &&
          sittingOk(t) &&
          (topicId == null || t.topicId == topicId) &&
          (priorities.isEmpty || priorities.contains(t.priority)))
        t,
  ];
  // A full paper sitting: essays first, then short, VSA, MCQ (printed order).
  if (paperName != null && year != null) {
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
    universityId: filter.universityId,
    year: filter.year,
    examType: filter.examType,
    paperName: filter.paperName,
    isMcq: filter.isMcq,
    topicId: filter.topicId,
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
PyqFilterOptions availableFilterOptions(
  List<PyqTeaser> teasers,
  SubjectPyqFilter filter,
) {
  final sittings = [for (final t in teasers) ...t.sittings];

  final universityIds = {for (final s in sittings) s.universityId};

  final underUniversity = [
    for (final s in sittings)
      if (filter.universityId == null || s.universityId == filter.universityId)
        s,
  ];
  final years = {for (final s in underUniversity) s.year};

  final underYear = [
    for (final s in underUniversity)
      if (filter.year == null || s.year == filter.year) s,
  ];
  final examTypes = {for (final s in underYear) s.examType};

  final underType = [
    for (final s in underYear)
      if (filter.examType == null || s.examType == filter.examType) s,
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

/// Drops any sitting-level pick that no longer exists under the picks above
/// it, so changing University does not leave a stale Year behind.
SubjectPyqFilter reconcileFilter(
  SubjectPyqFilter filter,
  List<PyqTeaser> teasers,
) {
  var next = SubjectPyqFilter(
    isMcq: filter.isMcq,
    topicId: filter.topicId,
    priorities: filter.priorities,
  );
  if (availableFilterOptions(
    teasers,
    next,
  ).universityIds.contains(filter.universityId)) {
    next = next.copyWith(universityId: filter.universityId);
  }
  if (availableFilterOptions(teasers, next).years.contains(filter.year)) {
    next = next.copyWith(year: filter.year);
  }
  if (availableFilterOptions(
    teasers,
    next,
  ).examTypes.contains(filter.examType)) {
    next = next.copyWith(examType: filter.examType);
  }
  if (availableFilterOptions(
    teasers,
    next,
  ).paperNames.contains(filter.paperName)) {
    next = next.copyWith(paperName: filter.paperName);
  }
  return next;
}
