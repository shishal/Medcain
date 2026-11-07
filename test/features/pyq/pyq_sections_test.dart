import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/pyq/domain/pyq_models.dart';
import 'package:medico/features/pyq/domain/pyq_sections.dart';
import 'package:medico/features/pyq/domain/subject_pyq_filters.dart';

PaperSitting _sitting({
  String university = 'u1',
  String? college,
  PaperExamType type = PaperExamType.prof,
  required int year,
  String? paper = 'Paper I',
}) {
  return PaperSitting(
    universityId: university,
    collegeId: college,
    examType: type,
    year: year,
    paperName: paper,
  );
}

PyqTeaser _teaser(String id, List<PaperSitting> sittings, {String? kind}) {
  return PyqTeaser(
    id: id,
    questionText: id,
    marks: 10,
    requiredPlan: PlanTier.free,
    appearanceCount: sittings.length,
    kind: kind ?? 'pyq_theory',
    sittings: sittings,
  );
}

PyqSections _build(
  List<PyqTeaser> teasers, {
  SubjectPyqFilter filter = const SubjectPyqFilter(),
}) {
  return buildPyqSections(
    teasers: teasers,
    filter: filter,
    userUniversityId: 'u1',
    userCollegeId: 'c1',
    universityCodes: const {'u1': 'GGSIPU', 'u2': 'KUHS', 'u3': 'RGUHS'},
  );
}

void main() {
  group('classifySitting', () {
    PyqSection classify(PaperSitting s) =>
        classifySitting(s, userUniversityId: 'u1');

    test('own university prof and supply are section one', () {
      expect(classify(_sitting(year: 2024)), PyqSection.ownUniversity);
      expect(
        classify(_sitting(year: 2024, type: PaperExamType.supply)),
        PyqSection.ownUniversity,
      );
    });

    test('own-university pre-prof and internal are section two', () {
      expect(
        classify(
          _sitting(year: 2025, college: 'c1', type: PaperExamType.preProf),
        ),
        PyqSection.ownCollege,
      );
      expect(
        classify(
          _sitting(year: 2025, college: 'c1', type: PaperExamType.internal),
        ),
        PyqSection.ownCollege,
      );
      // Other campuses of the same university stay in section two.
      expect(
        classify(
          _sitting(year: 2025, college: 'c2', type: PaperExamType.preProf),
        ),
        PyqSection.ownCollege,
      );
      // Campus papers with no college still sit with pre-prof / internal.
      expect(
        classify(_sitting(year: 2025, type: PaperExamType.preProf)),
        PyqSection.ownCollege,
      );
    });

    test('other universities are section three', () {
      expect(
        classify(_sitting(year: 2025, university: 'u2')),
        PyqSection.other,
      );
    });

    test('everything is "other" while the student has no university', () {
      expect(
        classifySitting(_sitting(year: 2024), userUniversityId: null),
        PyqSection.other,
      );
    });
  });

  group('buildPyqSections', () {
    final teasers = [
      _teaser('a', [_sitting(year: 2022)]),
      _teaser('b', [
        _sitting(year: 2024, paper: 'Paper I'),
        _sitting(year: 2024, paper: 'Paper II'),
      ]),
      _teaser('c', [_sitting(year: 2024, paper: 'Paper II')]),
      _teaser('d', [
        _sitting(year: 2026, college: 'c1', type: PaperExamType.preProf),
      ]),
      _teaser('d2', [
        _sitting(year: 2024, college: 'c2', type: PaperExamType.internal),
      ]),
      _teaser('d3', [
        _sitting(year: 2025, college: 'c1', type: PaperExamType.internal),
      ]),
      _teaser('e', [_sitting(year: 2023, university: 'u3')]),
      _teaser('f', [_sitting(year: 2021, university: 'u2')]),
      _teaser('g', [_sitting(year: 2025, university: 'u2')]),
    ];

    test('puts each sitting in its section, newest year then paper', () {
      final sections = _build(teasers);

      expect(sections.ownUniversity.map((g) => (g.year, g.paperName)), [
        (2024, 'Paper I'),
        (2024, 'Paper II'),
        (2022, 'Paper I'),
      ]);
      // Own college first (newest first), then other campuses.
      expect(
        sections.ownCollege.map((g) => (g.collegeId, g.year, g.paperName)),
        [
          ('c1', 2026, 'Paper I'),
          ('c1', 2025, 'Paper I'),
          ('c2', 2024, 'Paper I'),
        ],
      );
      // "Other" is grouped by university code (KUHS before RGUHS).
      expect(sections.other.map((g) => (g.universityId, g.year)), [
        ('u2', 2025),
        ('u2', 2021),
        ('u3', 2023),
      ]);
    });

    test('counts each question once per paper', () {
      final rows = _build(teasers).ownUniversity;
      expect(rows.first.paperName, 'Paper I');
      expect(rows.first.questionCount, 1);
      expect(rows[1].paperName, 'Paper II');
      // The stem that sat both papers is counted again on Paper II.
      expect(rows[1].questionCount, 2);
      expect(rows.first.examTypes, [PaperExamType.prof]);
    });

    test('a blank paper name is its own row after named papers', () {
      final sections = _build([
        _teaser('named', [_sitting(year: 2024, paper: 'Paper II')]),
        _teaser('blank', [_sitting(year: 2024, paper: null)]),
        _teaser('first', [_sitting(year: 2024, paper: 'Paper I')]),
      ]);
      expect(sections.ownUniversity.map((g) => g.paperLabel), [
        'Paper I',
        'Paper II',
        'Paper',
      ]);
    });

    test('applies the filter before grouping', () {
      final sections = _build(
        teasers,
        filter: const SubjectPyqFilter(examType: PaperExamType.preProf),
      );
      expect(sections.ownUniversity, isEmpty);
      expect(sections.ownCollege.single.year, 2026);
      expect(sections.other, isEmpty);
    });

    test('is empty when nothing matches', () {
      expect(_build(const []).isEmpty, isTrue);
    });
  });

  group('same-sitting rule', () {
    final teasers = [
      _teaser('q', [
        _sitting(year: 2023, paper: 'Paper I'),
        _sitting(year: 2024, paper: 'Paper II'),
      ]),
    ];

    test('year and paper must match on one sitting', () {
      expect(
        filterSubjectPyqs(teasers: teasers, year: 2023, paperName: 'Paper II'),
        isEmpty,
      );
      expect(
        filterSubjectPyqs(
          teasers: teasers,
          year: 2024,
          paperName: 'Paper II',
        ).single.id,
        'q',
      );
    });
  });

  group('filter cascade', () {
    final teasers = [
      _teaser('a', [_sitting(year: 2023, university: 'u1')]),
      _teaser('b', [
        _sitting(year: 2024, university: 'u2', type: PaperExamType.supply),
      ]),
    ];

    test('options narrow to what exists under the picks above', () {
      final all = availableFilterOptions(teasers, const SubjectPyqFilter());
      expect(all.universityIds, ['u1', 'u2']);
      expect(all.years, [2024, 2023]);

      final inU2 = availableFilterOptions(
        teasers,
        const SubjectPyqFilter(universityId: 'u2'),
      );
      expect(inU2.years, [2024]);
      expect(inU2.examTypes, [PaperExamType.supply]);
    });

    test('changing a parent clears a child that no longer exists', () {
      const picked = SubjectPyqFilter(
        universityId: 'u2',
        year: 2024,
        examType: PaperExamType.supply,
      );
      final moved = reconcileFilter(
        picked.copyWith(universityId: 'u1'),
        teasers,
      );
      expect(moved.universityId, 'u1');
      expect(moved.year, isNull);
      expect(moved.examType, isNull);

      final kept = reconcileFilter(picked, teasers);
      expect(kept.year, 2024);
      expect(kept.examType, PaperExamType.supply);
    });

    test('keeps the question-level picks while reconciling', () {
      final result = reconcileFilter(
        const SubjectPyqFilter(universityId: 'gone', isMcq: true, topicId: 't'),
        teasers,
      );
      expect(result.universityId, isNull);
      expect(result.isMcq, isTrue);
      expect(result.topicId, 't');
    });

    test('copyWith can clear a pick as well as keep it', () {
      const filter = SubjectPyqFilter(year: 2024, isMcq: true);
      expect(filter.copyWith(year: null).year, isNull);
      expect(filter.copyWith(topicId: 't').year, 2024);
      expect(filter.copyWith(isMcq: null).isMcq, isNull);
    });
  });
}
