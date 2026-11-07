import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/tests/domain/catalog_test.dart';
import 'package:medico/features/tests/domain/test_detail.dart';
import 'package:medico/features/tests/domain/test_type.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';

void main() {
  group('TestType', () {
    test('fromString maps known values', () {
      expect(TestType.fromString('mini'), TestType.mini);
      expect(TestType.fromString('SUBJECT'), TestType.subject);
      expect(TestType.fromString('mock'), TestType.mock);
      expect(TestType.fromString('grand'), TestType.grand);
    });

    test('label matches UI copy', () {
      expect(TestType.mini.label, 'Mini');
      expect(TestType.subject.label, 'Subject');
      expect(TestType.mock.label, 'Mock');
      expect(TestType.grand.label, 'Grand');
    });
  });

  group('PlanTier', () {
    test('covers mirrors plan_rank ordering', () {
      expect(PlanTier.free.covers(PlanTier.free), isTrue);
      expect(PlanTier.free.covers(PlanTier.pro), isFalse);
      expect(PlanTier.pro.covers(PlanTier.free), isTrue);
      expect(PlanTier.pro.covers(PlanTier.elite), isTrue);
      expect(PlanTier.elite.covers(PlanTier.pro), isTrue);
    });
  });

  group('CatalogTest', () {
    test('fromJson parses list fields', () {
      final test = CatalogTest.fromJson({
        'id': 't-1',
        'title': 'Mini Test 1',
        'test_type': 'mini',
        'required_plan': 'free',
        'is_sectional': false,
        'total_duration_minutes': 30,
        'total_questions': 20,
      });

      expect(test.id, 't-1');
      expect(test.title, 'Mini Test 1');
      expect(test.testType, TestType.mini);
      expect(test.requiredPlan, PlanTier.free);
      expect(test.totalDurationMinutes, 30);
      expect(test.totalQuestions, 20);
      expect(test.durationLabel, '30 min');
      expect(test.isLockedFor(PlanTier.free), isFalse);
    });

    test('isLockedFor when required plan is above user plan', () {
      final grand = CatalogTest(
        id: 'g',
        title: 'NEET-PG Grand Test 3',
        testType: TestType.grand,
        requiredPlan: PlanTier.pro,
        totalDurationMinutes: 210,
        totalQuestions: 180,
        isSectional: true,
      );

      expect(grand.isLockedFor(PlanTier.free), isTrue);
      expect(grand.isLockedFor(PlanTier.pro), isFalse);
    });

    test('durationLabel formats hours and minutes', () {
      final hourOnly = CatalogTest(
        id: 'a',
        title: 'A',
        testType: TestType.mock,
        requiredPlan: PlanTier.free,
        totalDurationMinutes: 120,
        totalQuestions: 100,
        isSectional: false,
      );
      final mixed = CatalogTest(
        id: 'b',
        title: 'B',
        testType: TestType.grand,
        requiredPlan: PlanTier.pro,
        totalDurationMinutes: 210,
        totalQuestions: 180,
        isSectional: true,
      );

      expect(hourOnly.durationLabel, '2h');
      expect(mixed.durationLabel, '3h 30m');
    });
  });

  group('TestDetail', () {
    test('fromJson parses marking and section fields', () {
      final detail = TestDetail.fromJson({
        'id': 'g-1',
        'title': 'Grand Test 1',
        'description': 'Full NEET-PG shape',
        'test_type': 'grand',
        'required_plan': 'pro',
        'is_sectional': true,
        'section_count': 5,
        'questions_per_section': 36,
        'section_duration_minutes': 42,
        'total_duration_minutes': 210,
        'total_questions': 180,
        'correct_marks': 4,
        'incorrect_marks': -1,
        'unattempted_marks': 0,
      });

      expect(detail.isSectional, isTrue);
      expect(detail.sectionCount, 5);
      expect(detail.questionsPerSection, 36);
      expect(detail.sectionDurationMinutes, 42);
      expect(detail.markingSchemeLabel, '+4 correct · −1 incorrect · 0 skipped');
      expect(
        detail.sectionLayoutLabel,
        '5 sections · 36 questions each · 42 min each',
      );
      expect(detail.durationLabel, '3h 30m');
    });

    test('sectionLayoutLabel is null for non-sectional tests', () {
      final detail = TestDetail(
        id: 'm',
        title: 'Mini',
        testType: TestType.mini,
        requiredPlan: PlanTier.free,
        isSectional: false,
        sectionCount: 1,
        totalDurationMinutes: 30,
        totalQuestions: 20,
        correctMarks: 4,
        incorrectMarks: -1,
        unattemptedMarks: 0,
      );

      expect(detail.sectionLayoutLabel, isNull);
      expect(detail.sectionDurationLabel, isNull);
    });
  });
}
