import 'pyq_models.dart';
import 'subject_pyq_filters.dart';

/// The three blocks on the subject PYQ screen.
enum PyqSection {
  /// The student's university: prof and supply papers.
  ownUniversity,

  /// The student's own college: pre-prof and internal papers.
  ownCollege,

  /// Everything else: other universities, and other colleges' campus papers.
  other,
}

/// Which block a sitting belongs to for this student.
PyqSection classifySitting(
  PaperSitting sitting, {
  required String? userUniversityId,
  required String? userCollegeId,
}) {
  if (userUniversityId == null || sitting.universityId != userUniversityId) {
    return PyqSection.other;
  }
  if (!sitting.examType.isCampusLevel) return PyqSection.ownUniversity;
  // A campus paper with no college on it cannot be tied to a campus, so it
  // reads as the university's own paper.
  if (sitting.collegeId == null) return PyqSection.ownUniversity;
  if (sitting.collegeId == userCollegeId) return PyqSection.ownCollege;
  return PyqSection.other;
}

/// One row on the subject screen: a university's papers in one year,
/// within one section.
class PyqSittingGroup {
  const PyqSittingGroup({
    required this.section,
    required this.universityId,
    required this.year,
    required this.examTypes,
    required this.paperNames,
    required this.questionCount,
  });

  final PyqSection section;
  final String universityId;
  final int year;
  final List<PaperExamType> examTypes;

  /// Sitting labels such as `October · Paper I`.
  final List<String> paperNames;
  final int questionCount;
}

class PyqSections {
  const PyqSections({
    this.ownUniversity = const [],
    this.ownCollege = const [],
    this.other = const [],
  });

  final List<PyqSittingGroup> ownUniversity;
  final List<PyqSittingGroup> ownCollege;
  final List<PyqSittingGroup> other;

  bool get isEmpty =>
      ownUniversity.isEmpty && ownCollege.isEmpty && other.isEmpty;
}

class _GroupBuilder {
  final questionIds = <String>{};
  final examTypes = <PaperExamType>{};
  final paperNames = <String>{};
}

/// Splits the filtered feed into the three sections. Years run newest first;
/// "other" is grouped by university first, using [universityCodes] for the
/// order so the screen can put a heading over each university.
PyqSections buildPyqSections({
  required List<PyqTeaser> teasers,
  required SubjectPyqFilter filter,
  required String? userUniversityId,
  required String? userCollegeId,
  Map<String, String> universityCodes = const {},
}) {
  final builders = <(PyqSection, String, int), _GroupBuilder>{};
  for (final teaser in applySubjectPyqFilter(teasers, filter)) {
    for (final sitting in teaser.sittings) {
      if (!sittingMatches(sitting, filter)) continue;
      final section = classifySitting(
        sitting,
        userUniversityId: userUniversityId,
        userCollegeId: userCollegeId,
      );
      final group = builders.putIfAbsent(
        (section, sitting.universityId, sitting.year),
        _GroupBuilder.new,
      );
      group.questionIds.add(teaser.id);
      group.examTypes.add(sitting.examType);
      if (sitting.paperName != null || sitting.month != null) {
        group.paperNames.add(sitting.label);
      }
    }
  }

  final groups = [
    for (final entry in builders.entries)
      PyqSittingGroup(
        section: entry.key.$1,
        universityId: entry.key.$2,
        year: entry.key.$3,
        examTypes: [
          for (final type in PaperExamType.values)
            if (entry.value.examTypes.contains(type)) type,
        ],
        paperNames: entry.value.paperNames.toList()..sort(),
        questionCount: entry.value.questionIds.length,
      ),
  ];

  String codeOf(PyqSittingGroup g) =>
      universityCodes[g.universityId] ?? g.universityId;

  List<PyqSittingGroup> pick(PyqSection section) {
    final list = [
      for (final g in groups)
        if (g.section == section) g,
    ];
    list.sort((a, b) {
      if (section == PyqSection.other) {
        final byUni = codeOf(a).compareTo(codeOf(b));
        if (byUni != 0) return byUni;
      }
      return b.year.compareTo(a.year);
    });
    return list;
  }

  return PyqSections(
    ownUniversity: pick(PyqSection.ownUniversity),
    ownCollege: pick(PyqSection.ownCollege),
    other: pick(PyqSection.other),
  );
}
