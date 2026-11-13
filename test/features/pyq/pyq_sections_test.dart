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
  int? month,
}) {
  return PaperSitting(
    universityId: university,
    collegeId: college,
    examType: type,
    year: year,
    month: month,
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
    universityCodes: const {
      'u1': 'GGSIPU',
      'u2': 'KUHS',
      'u3': 'RGUHS',
      'u4': 'AIIMS',
    },
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
      // AIIMS sorts first alphabetically, but its newest paper is older.
      _teaser('h', [_sitting(year: 2019, university: 'u4')]),
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
      // Newest university first, not A–Z: KUHS 2025, RGUHS 2023, AIIMS 2019.
      expect(sections.other.map((g) => (g.universityId, g.year)), [
        ('u2', 2025),
        ('u2', 2021),
        ('u3', 2023),
        ('u4', 2019),
      ]);
    });

    test('other universities with the same newest year stay alphabetical', () {
      final sections = _build([
        _teaser('rguhs', [_sitting(year: 2024, university: 'u3')]),
        _teaser('aiims', [
          _sitting(year: 2024, university: 'u4', paper: 'Paper II'),
          _sitting(year: 2020, university: 'u4', paper: 'Paper I'),
        ]),
        _teaser('kuhs', [_sitting(year: 2024, university: 'u2')]),
      ]);
      expect(sections.other.map((g) => (g.universityId, g.year)), [
        ('u4', 2024),
        ('u4', 2020),
        ('u2', 2024),
        ('u3', 2024),
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

    test('the same paper in two months is two rows, earlier month first', () {
      final sections = _build([
        _teaser('oct', [_sitting(year: 2024, month: 10)]),
        _teaser('aug-ii', [_sitting(year: 2024, paper: 'Paper II', month: 8)]),
        _teaser('aug-i', [_sitting(year: 2024, month: 8)]),
        _teaser('undated', [_sitting(year: 2024)]),
      ]);
      expect(sections.ownUniversity.map((g) => (g.month, g.paperLabel)), [
        (8, 'August · Paper I'),
        (8, 'August · Paper II'),
        (10, 'October · Paper I'),
        (null, 'Paper I'),
      ]);
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
        filter: const SubjectPyqFilter(examTypes: {PaperExamType.preProf}),
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
        filterSubjectPyqs(
          teasers: teasers,
          years: {2023},
          paperNames: {'Paper II'},
        ),
        isEmpty,
      );
      expect(
        filterSubjectPyqs(
          teasers: teasers,
          years: {2024},
          paperNames: {'Paper II'},
        ).single.id,
        'q',
      );
    });

    test('several years or papers match when one sitting hits each set', () {
      expect(
        filterSubjectPyqs(
          teasers: teasers,
          years: {2023, 2024},
          paperNames: {'Paper I', 'Paper II'},
        ).single.id,
        'q',
      );
      expect(
        filterSubjectPyqs(
          teasers: teasers,
          years: {2023},
          paperNames: {'Paper I', 'Paper II'},
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
        const SubjectPyqFilter(universityIds: {'u2'}),
      );
      expect(inU2.years, [2024]);
      expect(inU2.examTypes, [PaperExamType.supply]);

      final both = availableFilterOptions(
        teasers,
        const SubjectPyqFilter(universityIds: {'u1', 'u2'}),
      );
      expect(both.years, [2024, 2023]);
    });

    test('changing a parent drops a child that no longer exists', () {
      const picked = SubjectPyqFilter(
        universityIds: {'u2'},
        years: {2024},
        examTypes: {PaperExamType.supply},
      );
      final moved = reconcileFilter(
        picked.copyWith(universityIds: {'u1'}),
        teasers,
      );
      expect(moved.universityIds, {'u1'});
      expect(moved.years, isEmpty);
      expect(moved.examTypes, isEmpty);

      final kept = reconcileFilter(picked, teasers);
      expect(kept.years, {2024});
      expect(kept.examTypes, {PaperExamType.supply});
    });

    test('keeps a child that still exists under one remaining parent', () {
      const picked = SubjectPyqFilter(
        universityIds: {'u1', 'u2'},
        years: {2023, 2024},
      );
      final moved = reconcileFilter(
        picked.copyWith(universityIds: {'u1'}),
        teasers,
      );
      expect(moved.universityIds, {'u1'});
      expect(moved.years, {2023});
    });

    test('keeps the question-level picks while reconciling', () {
      final result = reconcileFilter(
        const SubjectPyqFilter(
          universityIds: {'gone'},
          questionKinds: {PyqQuestionKind.mcq},
          topicIds: {'t'},
        ),
        teasers,
      );
      expect(result.universityIds, isEmpty);
      expect(result.questionKinds, {PyqQuestionKind.mcq});
      expect(result.topicIds, {'t'});
    });

    test('copyWith can clear a pick as well as keep it', () {
      const filter = SubjectPyqFilter(
        years: {2024},
        questionKinds: {PyqQuestionKind.mcq},
      );
      expect(filter.copyWith(years: {}).years, isEmpty);
      expect(filter.copyWith(topicIds: {'t'}).years, {2024});
      expect(filter.copyWith(questionKinds: {}).questionKinds, isEmpty);
    });
  });
}
