import 'pyq_models.dart';
import 'subject_pyq_filters.dart';

/// The three blocks on the subject PYQ screen.
enum PyqSection {
  /// The student's university: prof and supply papers.
  ownUniversity,

  /// The student's university campus papers (pre-prof / internal),
  /// with the student's college listed first.
  ownCollege,

  /// Everything else: other universities.
  other,
}

/// Which block a sitting belongs to for this student.
///
/// College only changes order inside section two (see [buildPyqSections]);
/// every campus paper of the student's university is section two.
PyqSection classifySitting(
  PaperSitting sitting, {
  required String? userUniversityId,
}) {
  if (userUniversityId == null || sitting.universityId != userUniversityId) {
    return PyqSection.other;
  }
  if (sitting.examType.isCampusLevel) return PyqSection.ownCollege;
  return PyqSection.ownUniversity;
}

/// One row on the subject screen: one printed paper (Paper I, Paper II, …)
/// in one year, within one section (and one college, for campus papers).
class PyqSittingGroup {
  const PyqSittingGroup({
    required this.section,
    required this.universityId,
    this.collegeId,
    required this.year,
    required this.examTypes,
    this.paperName,
    required this.questionCount,
  });

  final PyqSection section;
  final String universityId;

  /// Set for campus-paper rows so the outline can open just that college.
  final String? collegeId;
  final int year;
  final List<PaperExamType> examTypes;

  /// Printed paper label such as `Paper I`. Null when the sheet left it blank.
  final String? paperName;
  final int questionCount;

  /// What the paper row shows. Blank sheet values still get a tappable row.
  String get paperLabel {
    final name = paperName?.trim();
    if (name == null || name.isEmpty) return 'Paper';
    return name;
  }
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
}

/// Roman and digit suffixes so Paper I sits above Paper II, not by alphabet.
const _paperRoman = {
  'i': 1,
  'ii': 2,
  'iii': 3,
  'iv': 4,
  'v': 5,
  'vi': 6,
  'vii': 7,
  'viii': 8,
  'ix': 9,
  'x': 10,
};

int _paperOrdinal(String? name) {
  if (name == null || name.trim().isEmpty) return 1000;
  final tail = name.trim().toLowerCase().split(RegExp(r'\s+')).last;
  return int.tryParse(tail) ?? _paperRoman[tail] ?? 500;
}

int _comparePaperNames(String? a, String? b) {
  final aBlank = a == null || a.trim().isEmpty;
  final bBlank = b == null || b.trim().isEmpty;
  if (aBlank != bBlank) return aBlank ? 1 : -1;
  final byNumber = _paperOrdinal(a).compareTo(_paperOrdinal(b));
  if (byNumber != 0) return byNumber;
  return (a ?? '').compareTo(b ?? '');
}

/// Splits the filtered feed into the three sections. Years run newest first,
/// and each year is one row per printed paper (Paper I, then Paper II).
/// Section 2 lists the student's college first, then other colleges of the
/// same university. "Other" is grouped by university using [universityCodes].
PyqSections buildPyqSections({
  required List<PyqTeaser> teasers,
  required SubjectPyqFilter filter,
  required String? userUniversityId,
  required String? userCollegeId,
  Map<String, String> universityCodes = const {},
}) {
  // Key: section, university, college (campus rows only), year, paper name.
  final builders = <(PyqSection, String, String, int, String), _GroupBuilder>{};
  for (final teaser in applySubjectPyqFilter(teasers, filter)) {
    for (final sitting in teaser.sittings) {
      if (!sittingMatches(sitting, filter)) continue;
      final section = classifySitting(
        sitting,
        userUniversityId: userUniversityId,
      );
      // Keep campus papers of the same uni/year as separate rows per college;
      // prof/supply and other-university rows stay one per uni/year/paper.
      final collegeKey = section == PyqSection.ownCollege
          ? (sitting.collegeId ?? '')
          : '';
      final paperKey = sitting.paperName?.trim() ?? '';
      final group = builders.putIfAbsent((
        section,
        sitting.universityId,
        collegeKey,
        sitting.year,
        paperKey,
      ), _GroupBuilder.new);
      group.questionIds.add(teaser.id);
      group.examTypes.add(sitting.examType);
    }
  }

  final groups = [
    for (final entry in builders.entries)
      PyqSittingGroup(
        section: entry.key.$1,
        universityId: entry.key.$2,
        collegeId: entry.key.$3.isEmpty ? null : entry.key.$3,
        year: entry.key.$4,
        examTypes: [
          for (final type in PaperExamType.values)
            if (entry.value.examTypes.contains(type)) type,
        ],
        paperName: entry.key.$5.isEmpty ? null : entry.key.$5,
        questionCount: entry.value.questionIds.length,
      ),
  ];

  String codeOf(PyqSittingGroup g) =>
      universityCodes[g.universityId] ?? g.universityId;

  int collegeRank(PyqSittingGroup g) {
    if (userCollegeId != null && g.collegeId == userCollegeId) return 0;
    if (g.collegeId == null) return 1;
    return 2;
  }

  List<PyqSittingGroup> pick(PyqSection section) {
    final list = [
      for (final g in groups)
        if (g.section == section) g,
    ];
    list.sort((a, b) {
      if (section == PyqSection.ownCollege) {
        final byRank = collegeRank(a).compareTo(collegeRank(b));
        if (byRank != 0) return byRank;
        final byCollege = (a.collegeId ?? '').compareTo(b.collegeId ?? '');
        if (byCollege != 0) return byCollege;
      }
      if (section == PyqSection.other) {
        final byUni = codeOf(a).compareTo(codeOf(b));
        if (byUni != 0) return byUni;
      }
      final byYear = b.year.compareTo(a.year);
      if (byYear != 0) return byYear;
      return _comparePaperNames(a.paperName, b.paperName);
    });
    return list;
  }

  return PyqSections(
    ownUniversity: pick(PyqSection.ownUniversity),
    ownCollege: pick(PyqSection.ownCollege),
    other: pick(PyqSection.other),
  );
}
