import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/utils/user_facing_error.dart';
import 'package:medico/features/practice/domain/plan_limits.dart';
import 'package:medico/features/practice/domain/practice_catalog.dart';
import 'package:medico/features/practice/presentation/providers/practice_catalog_provider.dart';
import 'package:medico/features/practice/presentation/providers/practice_plan_context_provider.dart';
import 'package:medico/features/practice/presentation/screens/practice_builder_screen.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';

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

Future<void> _pumpBuilder(
  WidgetTester tester, {
  required PracticeCatalogNotifier catalog,
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
}
