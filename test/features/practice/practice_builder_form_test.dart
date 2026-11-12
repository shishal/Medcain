import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/practice/domain/plan_limits.dart';
import 'package:medico/features/practice/domain/practice_builder_draft.dart';
import 'package:medico/features/practice/domain/practice_catalog.dart';
import 'package:medico/features/practice/domain/practice_enums.dart';
import 'package:medico/features/practice/presentation/widgets/practice_builder_form.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';

void main() {
  const catalog = PracticeCatalog(
    subjects: [Subject(id: 'med', name: 'Medicine', displayOrder: 0)],
    topics: [
      Topic(id: 'card', subjectId: 'med', name: 'Cardio', displayOrder: 0),
    ],
    tags: [PracticeTag(id: 'pyq', name: 'PYQ')],
  );

  const freeContext = PracticePlanContext(
    limits: PlanLimits(
      plan: PlanTier.free,
      maxPracticeSessionQuestions: 10,
      dailyPracticeQuestionQuota: 20,
      allowFullExplanation: false,
      allowTimerToggle: false,
      allowTagFilter: false,
      allowDifficultyFilter: true,
      allowNegativeMarkingToggle: false,
    ),
    questionsUsedToday: 0,
  );

  const proContext = PracticePlanContext(
    limits: PlanLimits(
      plan: PlanTier.pro,
      maxPracticeSessionQuestions: 50,
      dailyPracticeQuestionQuota: null,
      allowFullExplanation: true,
      allowTimerToggle: true,
      allowTagFilter: true,
      allowDifficultyFilter: true,
      allowNegativeMarkingToggle: true,
    ),
    questionsUsedToday: 0,
  );

  Future<void> pumpForm(WidgetTester tester, PracticePlanContext ctx) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeBuilderForm(
            draft: const PracticeBuilderDraft().clampedTo(ctx),
            catalog: catalog,
            planContext: ctx,
            onChanged: (_) {},
            onUpgrade: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('Filters'));
    await tester.pumpAndSettle();
  }

  testWidgets('free plan shows locked controls with upgrade hints', (
    tester,
  ) async {
    await pumpForm(tester, freeContext);

    expect(find.text('Upgrade to filter by tags'), findsOneWidget);
    expect(find.text('Upgrade to turn the timer off'), findsOneWidget);
    expect(find.text('Upgrade to Pro for full explanations'), findsOneWidget);
    expect(
      find.text('Upgrade to practice with exam-style negative marking'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Free plan allows up to 10 per session'),
      findsOneWidget,
    );

    expect(find.text('Subjects'), findsOneWidget);
    expect(find.text('Topics'), findsOneWidget);
    // Tags are visible (not hidden) even though locked.
    expect(find.text('#PYQ'), findsOneWidget);
    expect(find.text('Difficulty'), findsNothing);
    expect(find.text('Easy'), findsNothing);
    expect(find.text('Upgrade to filter by difficulty'), findsNothing);
  });

  testWidgets('similar-again draft is shown clamped for free', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const stored = PracticeBuilderDraft(
      selectedTagIds: {'pyq'},
      selectedTopicIds: {'card'},
      sourceFilter: QuestionSourceFilter.incorrect,
      questionCount: 80,
      feedbackTiming: FeedbackTiming.onSubmit,
      explanationLevel: ExplanationLevel.full,
      timerEnabled: false,
      negativeMarking: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeBuilderForm(
            draft: stored.clampedTo(freeContext),
            catalog: catalog,
            planContext: freeContext,
            onChanged: (_) {},
            onUpgrade: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('Filters'));
    await tester.pumpAndSettle();

    expect(find.text('10 questions'), findsOneWidget);
    expect(find.text('Previously Incorrect'), findsOneWidget);
    expect(find.text('Exam Mode'), findsOneWidget);
    expect(find.text('Answer only'), findsOneWidget);
    expect(find.text('Upgrade to filter by tags'), findsOneWidget);
  });

  testWidgets('pro plan leaves tag/timer/explanation controls unlocked', (
    tester,
  ) async {
    await pumpForm(tester, proContext);

    expect(find.text('Upgrade to filter by tags'), findsNothing);
    expect(find.text('Upgrade to turn the timer off'), findsNothing);
    expect(find.text('Upgrade to Pro for full explanations'), findsNothing);
    expect(
      find.text('Upgrade to practice with exam-style negative marking'),
      findsNothing,
    );
    expect(
      find.textContaining('Pro plan allows up to 50 per session'),
      findsOneWidget,
    );
    expect(find.text('Full explanation'), findsOneWidget);
  });
}
