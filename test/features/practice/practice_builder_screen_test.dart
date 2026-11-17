import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/utils/user_facing_error.dart';
import 'package:medico/features/practice/domain/plan_limits.dart';
import 'package:medico/features/practice/domain/practice_catalog.dart';
import 'package:medico/features/practice/domain/practice_enums.dart';
import 'package:medico/features/practice/domain/practice_slot.dart';
import 'package:medico/features/practice/presentation/providers/practice_catalog_provider.dart';
import 'package:medico/features/practice/presentation/providers/practice_plan_context_provider.dart';
import 'package:medico/features/practice/presentation/providers/practice_slot_provider.dart';
import 'package:medico/features/practice/presentation/screens/practice_builder_screen.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/tests/domain/attempt_status.dart';

class _EmptyCatalog extends PracticeCatalogNotifier {
  @override
  Future<PracticeCatalog> build() async {
    return const PracticeCatalog(subjects: [], topics: [], tags: []);
  }
}

class _ErrorCatalog extends PracticeCatalogNotifier {
  @override
  Future<PracticeCatalog> build() async {
    throw Exception(UserFacingError.offlineMessage);
  }
}

class _StubPlanContext extends PracticePlanContextNotifier {
  @override
  Future<PracticePlanContext> build() async {
    return const PracticePlanContext(
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
  }
}

class _NoSlot extends PracticeSlotNotifier {
  @override
  Future<PracticeSlot?> build() async => null;
}

class _OpenSlot extends PracticeSlotNotifier {
  @override
  Future<PracticeSlot?> build() async {
    return const PracticeSlot(
      testId: 'practice-1',
      feedbackTiming: FeedbackTiming.immediate,
      attemptId: 'attempt-1',
      attemptStatus: AttemptStatus.inProgress,
    );
  }
}

class _SubmittedSlot extends PracticeSlotNotifier {
  @override
  Future<PracticeSlot?> build() async {
    return const PracticeSlot(
      testId: 'practice-1',
      feedbackTiming: FeedbackTiming.onSubmit,
      attemptId: 'attempt-1',
      attemptStatus: AttemptStatus.submitted,
    );
  }
}

class _ReadyCatalog extends PracticeCatalogNotifier {
  @override
  Future<PracticeCatalog> build() async {
    return const PracticeCatalog(
      subjects: [Subject(id: 'med', name: 'Medicine', displayOrder: 0)],
      topics: [
        Topic(id: 'card', subjectId: 'med', name: 'Cardio', displayOrder: 0),
      ],
      tags: [],
    );
  }
}

Future<void> _pumpBuilder(
  WidgetTester tester, {
  required PracticeCatalogNotifier catalog,
  PracticeSlotNotifier? slot,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practiceCatalogProvider.overrideWith(() => catalog),
        practicePlanContextProvider.overrideWith(_StubPlanContext.new),
        practiceSlotProvider.overrideWith(() => slot ?? _NoSlot()),
      ],
      child: const MaterialApp(home: PracticeBuilderScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty catalog shows an empty state', (tester) async {
    await _pumpBuilder(tester, catalog: _EmptyCatalog());

    expect(find.text('No practice content is available yet.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('error state shows offline copy and Retry', (tester) async {
    await _pumpBuilder(tester, catalog: _ErrorCatalog());

    expect(find.text(UserFacingError.offlineMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('no open session offers Start practice and hides Resume', (
    tester,
  ) async {
    await _pumpBuilder(tester, catalog: _ReadyCatalog());

    expect(find.text('Start practice'), findsOneWidget);
    expect(find.text('Resume'), findsNothing);
  });

  testWidgets('an open session offers Resume and confirms Start new', (
    tester,
  ) async {
    await _pumpBuilder(tester, catalog: _ReadyCatalog(), slot: _OpenSlot());

    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Start new'), findsOneWidget);
    expect(find.text('Start practice'), findsNothing);

    await tester.tap(find.text('Start new'));
    await tester.pumpAndSettle();

    expect(find.text('Start a new practice?'), findsOneWidget);
    expect(
      find.text(
        'This replaces your current practice. Questions you already answered stay marked as attempted.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Start a new practice?'), findsNothing);
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('a submitted session has no Resume', (tester) async {
    await _pumpBuilder(
      tester,
      catalog: _ReadyCatalog(),
      slot: _SubmittedSlot(),
    );

    expect(find.text('Resume'), findsNothing);
    expect(find.text('Start practice'), findsOneWidget);
  });
}
