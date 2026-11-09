import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/supabase/tables.dart';
import 'package:medico/features/practice/domain/created_practice_session.dart';
import 'package:medico/features/practice/domain/plan_limits.dart';
import 'package:medico/features/practice/domain/practice_builder_draft.dart';
import 'package:medico/features/practice/domain/practice_catalog.dart';
import 'package:medico/features/practice/domain/practice_clamp_copy.dart';
import 'package:medico/features/practice/domain/practice_enums.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';

void main() {
  const freeLimits = PlanLimits(
    plan: PlanTier.free,
    maxPracticeSessionQuestions: 10,
    dailyPracticeQuestionQuota: 20,
    allowFullExplanation: false,
    allowTimerToggle: false,
    allowTagFilter: false,
    allowDifficultyFilter: true,
    allowNegativeMarkingToggle: false,
  );

  const proLimits = PlanLimits(
    plan: PlanTier.pro,
    maxPracticeSessionQuestions: 50,
    dailyPracticeQuestionQuota: null,
    allowFullExplanation: true,
    allowTimerToggle: true,
    allowTagFilter: true,
    allowDifficultyFilter: true,
    allowNegativeMarkingToggle: true,
  );

  group('PracticeBuilderDraft.clampedTo', () {
    test('caps question count and forces locked fields for free', () {
      const draft = PracticeBuilderDraft(
        selectedTagIds: {'tag-1'},
        questionCount: 80,
        explanationLevel: ExplanationLevel.full,
        timerEnabled: false,
        negativeMarking: true,
      );

      final clamped = draft.clampedTo(
        const PracticePlanContext(limits: freeLimits, questionsUsedToday: 0),
      );

      expect(clamped.questionCount, 10);
      expect(clamped.selectedTagIds, isEmpty);
      expect(clamped.explanationLevel, ExplanationLevel.answerOnly);
      expect(clamped.timerEnabled, isTrue);
      expect(clamped.negativeMarking, isFalse);
    });

    test('hasContentFilters is true when any chip set is non-empty', () {
      expect(const PracticeBuilderDraft().hasContentFilters, isFalse);
      expect(
        const PracticeBuilderDraft(selectedSubjectIds: {'med'})
            .hasContentFilters,
        isTrue,
      );
      expect(
        const PracticeBuilderDraft(selectedSubjectIds: {'med'})
            .clearContentFilters()
            .hasContentFilters,
        isFalse,
      );
    });

    test('caps to remaining daily quota when lower than session max', () {
      const draft = PracticeBuilderDraft(questionCount: 10);

      final clamped = draft.clampedTo(
        const PracticePlanContext(limits: freeLimits, questionsUsedToday: 16),
      );

      expect(clamped.questionCount, 4);
    });

    test('leaves pro selections intact', () {
      const draft = PracticeBuilderDraft(
        selectedTagIds: {'tag-1'},
        questionCount: 40,
        explanationLevel: ExplanationLevel.full,
        timerEnabled: false,
        negativeMarking: true,
      );

      final clamped = draft.clampedTo(
        const PracticePlanContext(limits: proLimits, questionsUsedToday: 0),
      );

      expect(clamped.questionCount, 40);
      expect(clamped.selectedTagIds, {'tag-1'});
      expect(clamped.explanationLevel, ExplanationLevel.full);
      expect(clamped.timerEnabled, isFalse);
      expect(clamped.negativeMarking, isTrue);
    });
  });

  group('PracticeBuilderDraft.resolvedTopicIds', () {
    const catalog = PracticeCatalog(
      subjects: [
        Subject(id: 'med', name: 'Medicine', displayOrder: 0),
        Subject(id: 'surg', name: 'Surgery', displayOrder: 1),
      ],
      topics: [
        Topic(id: 'card', subjectId: 'med', name: 'Cardio', displayOrder: 0),
        Topic(id: 'gi', subjectId: 'med', name: 'GI', displayOrder: 1),
        Topic(id: 'ortho', subjectId: 'surg', name: 'Ortho', displayOrder: 0),
      ],
      tags: [],
    );

    test('null when nothing selected (all topics)', () {
      const draft = PracticeBuilderDraft();
      expect(draft.resolvedTopicIds(catalog), isNull);
    });

    test('explicit topics win and are not also sent as subjects', () {
      const draft = PracticeBuilderDraft(
        selectedSubjectIds: {'med'},
        selectedTopicIds: {'card'},
      );
      expect(draft.resolvedTopicIds(catalog), ['card']);
      expect(draft.resolvedSubjectIds(catalog), isNull);
    });

    test('subject-only selection is sent as subjects, not every topic', () {
      const draft = PracticeBuilderDraft(selectedSubjectIds: {'med'});
      expect(draft.resolvedTopicIds(catalog), isNull);
      expect(draft.resolvedSubjectIds(catalog), ['med']);
    });
  });

  group('PracticeClampCopy', () {
    test('explains a plan-limit clamp', () {
      const requested = PracticeBuilderDraft(questionCount: 999);
      const actual = CreatedPracticeSession(
        testId: 't',
        totalQuestions: 10,
        explanationLevel: ExplanationLevel.answerOnly,
        timerEnabled: true,
        totalDurationMinutes: 10,
      );

      expect(
        PracticeClampCopy.toast(
          requested: requested,
          actual: actual,
          maxSessionQuestions: 10,
        ),
        "Showing 10 questions — your plan's practice limit",
      );
    });

    test('explains a full-explanation downgrade', () {
      const requested = PracticeBuilderDraft(
        questionCount: 10,
        explanationLevel: ExplanationLevel.full,
      );
      const actual = CreatedPracticeSession(
        testId: 't',
        totalQuestions: 10,
        explanationLevel: ExplanationLevel.answerOnly,
        timerEnabled: true,
        totalDurationMinutes: 10,
      );

      expect(
        PracticeClampCopy.toast(
          requested: requested,
          actual: actual,
          maxSessionQuestions: 10,
        ),
        "Full explanations aren't on your plan — showing the correct answer only",
      );
    });

    test('silent when the server honored the request', () {
      const requested = PracticeBuilderDraft(questionCount: 10);
      const actual = CreatedPracticeSession(
        testId: 't',
        totalQuestions: 10,
        explanationLevel: ExplanationLevel.answerOnly,
        timerEnabled: true,
        totalDurationMinutes: 10,
      );

      expect(
        PracticeClampCopy.toast(
          requested: requested,
          actual: actual,
          maxSessionQuestions: 10,
        ),
        isNull,
      );
    });
  });

  group('PracticeBuilderDraft.fromPracticeTestRow', () {
    test('restores requested filters from stored JSON', () {
      final draft = PracticeBuilderDraft.fromPracticeTestRow({
        TestColumns.feedbackTiming: 'on_submit',
        TestColumns.showExplanationLevel: 'answer_only',
        TestColumns.timerEnabled: true,
        TestColumns.totalQuestions: 10,
        TestColumns.practiceFilterCriteria: {
          PracticeFilterCriteriaKeys.topicIds: ['card', 'gi'],
          PracticeFilterCriteriaKeys.tagIds: ['pyq'],
          PracticeFilterCriteriaKeys.difficulties: ['hard'],
          PracticeFilterCriteriaKeys.sourceFilter: 'incorrect',
          PracticeFilterCriteriaKeys.requestedQuestionCount: 40,
          PracticeFilterCriteriaKeys.requestedExplanationLevel: 'full',
          PracticeFilterCriteriaKeys.negativeMarking: true,
          PracticeFilterCriteriaKeys.timerMinutes: 25,
        },
      });

      expect(draft.selectedTopicIds, {'card', 'gi'});
      expect(draft.selectedTagIds, {'pyq'});
      expect(draft.selectedDifficulties, isEmpty);
      expect(draft.resolvedDifficulties, isNull);
      expect(draft.sourceFilter, QuestionSourceFilter.incorrect);
      expect(draft.questionCount, 40);
      expect(draft.feedbackTiming, FeedbackTiming.onSubmit);
      expect(draft.explanationLevel, ExplanationLevel.full);
      expect(draft.timerEnabled, isTrue);
      expect(draft.timerMinutes, 25);
      expect(draft.negativeMarking, isTrue);
    });

    test('never applies stored difficulty to a new session', () {
      const draft = PracticeBuilderDraft(
        selectedDifficulties: {QuestionPriority.must},
      );
      expect(draft.hasContentFilters, isFalse);
      expect(draft.resolvedDifficulties, isNull);

      final clamped = draft.clampedTo(
        const PracticePlanContext(limits: proLimits, questionsUsedToday: 0),
      );
      expect(clamped.selectedDifficulties, isEmpty);
    });

    test('null JSON arrays mean no filter, timer null means off', () {
      final draft = PracticeBuilderDraft.fromPracticeTestRow({
        TestColumns.feedbackTiming: 'immediate',
        TestColumns.showExplanationLevel: 'answer_only',
        TestColumns.timerEnabled: false,
        TestColumns.totalQuestions: 8,
        TestColumns.practiceFilterCriteria: {
          PracticeFilterCriteriaKeys.topicIds: null,
          PracticeFilterCriteriaKeys.tagIds: null,
          PracticeFilterCriteriaKeys.difficulties: null,
          PracticeFilterCriteriaKeys.sourceFilter: 'all',
          PracticeFilterCriteriaKeys.requestedQuestionCount: 8,
          PracticeFilterCriteriaKeys.requestedExplanationLevel: 'none',
          PracticeFilterCriteriaKeys.negativeMarking: false,
          PracticeFilterCriteriaKeys.timerMinutes: null,
        },
      });

      expect(draft.selectedTopicIds, isEmpty);
      expect(draft.selectedTagIds, isEmpty);
      expect(draft.selectedDifficulties, isEmpty);
      expect(draft.sourceFilter, QuestionSourceFilter.all);
      expect(draft.explanationLevel, ExplanationLevel.none);
      expect(draft.timerEnabled, isFalse);
    });

    test('re-clamps stored filters against the current plan', () {
      // A session generated while Pro; user is now on Free.
      final stored = PracticeBuilderDraft.fromPracticeTestRow({
        TestColumns.feedbackTiming: 'immediate',
        TestColumns.showExplanationLevel: 'full',
        TestColumns.timerEnabled: false,
        TestColumns.totalQuestions: 40,
        TestColumns.practiceFilterCriteria: {
          PracticeFilterCriteriaKeys.tagIds: ['pyq'],
          PracticeFilterCriteriaKeys.requestedQuestionCount: 80,
          PracticeFilterCriteriaKeys.requestedExplanationLevel: 'full',
          PracticeFilterCriteriaKeys.negativeMarking: true,
          PracticeFilterCriteriaKeys.timerMinutes: null,
        },
      });

      final clamped = stored.clampedTo(
        const PracticePlanContext(limits: freeLimits, questionsUsedToday: 0),
      );

      expect(clamped.questionCount, 10);
      expect(clamped.selectedTagIds, isEmpty);
      expect(clamped.explanationLevel, ExplanationLevel.answerOnly);
      expect(clamped.timerEnabled, isTrue);
      expect(clamped.negativeMarking, isFalse);
    });
  });

  group('PracticeBuilderDraft.alignedWithCatalog', () {
    const catalog = PracticeCatalog(
      subjects: [Subject(id: 'med', name: 'Medicine', displayOrder: 0)],
      topics: [
        Topic(id: 'card', subjectId: 'med', name: 'Cardio', displayOrder: 0),
      ],
      tags: [PracticeTag(id: 'pyq', name: 'PYQ')],
    );

    test('infers subjects from topics and drops unknown ids', () {
      const draft = PracticeBuilderDraft(
        selectedTopicIds: {'card', 'gone'},
        selectedTagIds: {'pyq', 'retired'},
      );

      final aligned = draft.alignedWithCatalog(catalog);

      expect(aligned.selectedTopicIds, {'card'});
      expect(aligned.selectedTagIds, {'pyq'});
      expect(aligned.selectedSubjectIds, {'med'});
    });
  });

  group('PracticePlanContext', () {
    test('maxSelectableQuestions uses remaining quota', () {
      const ctx = PracticePlanContext(
        limits: freeLimits,
        questionsUsedToday: 15,
      );
      expect(ctx.remainingToday, 5);
      expect(ctx.maxSelectableQuestions, 5);
      expect(ctx.dailyQuotaExhausted, isFalse);
    });

    test('unlimited quota when daily cap is null', () {
      const ctx = PracticePlanContext(
        limits: proLimits,
        questionsUsedToday: 99,
      );
      expect(ctx.remainingToday, isNull);
      expect(ctx.maxSelectableQuestions, 50);
      expect(ctx.dailyQuotaExhausted, isFalse);
    });
  });
}
