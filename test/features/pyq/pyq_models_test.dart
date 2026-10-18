import 'package:flutter_test/flutter_test.dart';
import 'package:medico/core/supabase/tables.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/pyq/domain/pyq_models.dart';
import 'package:medico/features/progress/domain/progress_models.dart';

void main() {
  test('paper label includes the sitting month', () {
    expect(
      paperSittingLabel(month: 10, paperName: 'Paper I'),
      'October · Paper I',
    );
    expect(paperSittingLabel(paperName: 'Paper II'), 'Paper II');
    expect(examMonthName(13), isNull);
    expect(examMonthName(3), 'March');
  });

  test('PyqTeaser parses appearance_count', () {
    final teaser = PyqTeaser.fromJson({
      PyqTeaserColumns.id: 'q1',
      PyqTeaserColumns.lessonId: 'l1',
      PyqTeaserColumns.questionText: 'Describe the brachial plexus.',
      PyqTeaserColumns.marks: 10,
      PyqTeaserColumns.requiredPlan: 'free',
      PyqTeaserColumns.appearanceCount: 3,
    });
    expect(teaser.appearanceCount, 3);
    expect(teaser.requiredPlan, PlanTier.free);
    expect(teaser.marks, 10);
    expect(teaser.kind, 'pyq_theory');
    expect(teaser.isHighYield, isTrue);
    expect(teaser.format.label, 'Essay');
    // A blank difficulty cell imports as `should`, which carries no signal.
    expect(teaser.priority.label, 'Should');
    expect(teaser.priority.isNoteworthy, isFalse);
  });

  test('PyqTeaser reads an explicit must priority', () {
    final teaser = PyqTeaser.fromJson({
      PyqTeaserColumns.id: 'q-must',
      PyqTeaserColumns.questionText: 'Name the cranial nerves.',
      PyqTeaserColumns.requiredPlan: 'free',
      PyqTeaserColumns.appearanceCount: 1,
      PyqTeaserColumns.difficulty: 'must',
    });
    expect(teaser.priority.label, 'Must');
    expect(teaser.priority.isNoteworthy, isTrue);
  });

  test('PyqTeaser reads kind for MCQ and is not high-yield at 1×', () {
    final teaser = PyqTeaser.fromJson({
      PyqTeaserColumns.id: 'q2',
      PyqTeaserColumns.questionText: 'Axillary nerve supplies?',
      PyqTeaserColumns.requiredPlan: 'free',
      PyqTeaserColumns.appearanceCount: 1,
      PyqTeaserColumns.kind: 'mcq',
    });
    expect(teaser.kind, 'mcq');
    expect(teaser.isHighYield, isFalse);
    expect(teaser.format.label, 'MCQ');
  });

  test('SearchHits maps subjects lessons and PYQ stems', () {
    final hits = SearchHits.fromJson({
      'subjects': [
        {'id': 's1', 'name': 'Anatomy'},
      ],
      'lessons': [
        {'id': 'l1', 'name': 'Brachial plexus', 'required_plan': 'free'},
      ],
      'questions': [
        {'id': 'q1', 'question_text': 'Describe Erb palsy.', 'lesson_id': 'l1'},
      ],
    });
    expect(hits.subjects.single.title, 'Anatomy');
    expect(hits.lessons.single.kind, 'lesson');
    expect(hits.questions.single.title, 'Describe Erb palsy.');
  });

  test('TextbookCitation formats book, edition, and page', () {
    final citation = TextbookCitation.fromJson({
      TextbookRefColumns.page: 48,
      TextbookRefColumns.sectionHeading: 'Brachial plexus',
      TextbookRefColumns.textbookEmbed: {
        TextbookColumns.title: "BD Chaurasia's Human Anatomy Vol 1",
        TextbookColumns.edition: '8th',
      },
    });
    expect(citation.label, contains('p. 48'));
    expect(citation.label, contains('8th'));
    expect(citation.label, contains('Brachial plexus'));
  });

  test('StudyProgress parses streak JSON from RPC', () {
    final progress = StudyProgress.fromJson({
      'streak': 2,
      'days7': [
        {'date': '2026-08-29', 'count': 1},
        {'date': '2026-08-30', 'count': 3},
      ],
      'days30': <Map<String, dynamic>>[],
      'subjects': [
        {
          'id': 's1',
          'name': 'Anatomy',
          'learnt_lessons': 1,
          'total_lessons': 4,
          'total_pyqs': 12,
        },
      ],
    });
    expect(progress.streak, 2);
    expect(progress.days7.last.count, 3);
    expect(progress.subjects.single.totalLessons, 4);
    expect(progress.subjects.single.totalPyqs, 12);
  });
}
