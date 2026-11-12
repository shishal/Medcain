import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/router/app_routes.dart';
import 'package:medico/core/utils/user_facing_error.dart';
import 'package:medico/features/results/domain/attempt_results.dart';
import 'package:medico/features/results/presentation/providers/attempt_results_provider.dart';
import 'package:medico/features/results/presentation/screens/results_screen.dart';
import 'package:medico/features/results/presentation/widgets/results_summary.dart';

AttemptResults _results({bool isPractice = false, bool neetMarking = true}) {
  return AttemptResults(
    attemptId: 'a1',
    testId: 't1',
    testTitle: 'Mini Test 1',
    totalScore: neetMarking ? 7 : 2,
    correctCount: 2,
    incorrectCount: 1,
    unattemptedCount: 1,
    percentile: 50,
    durationSeconds: 125,
    correctMarks: neetMarking ? 4 : 1,
    incorrectMarks: neetMarking ? -1 : 0,
    unattemptedMarks: 0,
    isEphemeralPractice: isPractice,
    subjects: const [
      SubjectBreakdown(
        subjectId: 's-med',
        subjectName: 'Medicine',
        correctCount: 1,
        incorrectCount: 1,
        unattemptedCount: 0,
      ),
      SubjectBreakdown(
        subjectId: 's-surg',
        subjectName: 'Surgery',
        correctCount: 1,
        incorrectCount: 0,
        unattemptedCount: 1,
      ),
    ],
  );
}

Future<void> _pumpResults(
  WidgetTester tester, {
  required AttemptResults results,
  bool isPractice = false,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [attemptResultsProvider.overrideWith((ref, id) => results)],
      child: MaterialApp(
        home: ResultsScreen(
          attemptId: results.attemptId,
          testId: results.testId,
          isPractice: isPractice,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows Practice Similar Again only for practice sessions', (
    tester,
  ) async {
    await _pumpResults(
      tester,
      results: _results(isPractice: true, neetMarking: false),
      isPractice: true,
    );

    expect(find.text('Practice Similar Again'), findsOneWidget);
  });

  testWidgets('hides Practice Similar Again for catalog results', (
    tester,
  ) async {
    await _pumpResults(tester, results: _results());

    expect(find.text('Practice Similar Again'), findsNothing);
  });

  testWidgets('shows score, accuracy, percentile, time, and subjects', (
    tester,
  ) async {
    await _pumpResults(tester, results: _results());

    expect(find.text('Mini Test 1'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Score out of 16'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('Correct'), findsOneWidget);
    expect(find.text('Incorrect'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('Accuracy'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Percentile'), findsOneWidget);
    expect(find.text('Time spent'), findsOneWidget);
    expect(find.text('2m 5s'), findsOneWidget);
    expect(find.text('Medicine'), findsOneWidget);
    expect(find.text('Surgery'), findsOneWidget);
    expect(find.text('1 correct · 1 incorrect · 0 skipped'), findsOneWidget);
    expect(find.text('1 correct · 0 incorrect · 1 skipped'), findsOneWidget);
    expect(find.text('Review solutions'), findsOneWidget);
  });

  testWidgets('practice without negative marking leads with accuracy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultsSummary(
            results: _results(isPractice: true, neetMarking: false),
          ),
        ),
      ),
    );

    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Accuracy'), findsOneWidget);
    expect(find.text('Score out of 16'), findsNothing);
    expect(find.text('Percentile'), findsNothing);
  });

  test('resultsPath includes practice query flags', () {
    expect(
      AppRoutes.resultsPath('a1', testId: 't1', isPractice: true),
      '/results/a1?testId=t1&practice=1',
    );
    expect(AppRoutes.resultsPath('a1'), '/results/a1');
    expect(AppRoutes.solutionReviewPath('a1'), '/results/a1/review');
  });

  testWidgets('error state shows offline copy and Retry', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attemptResultsProvider.overrideWith(
            (ref, id) => throw Exception(UserFacingError.offlineMessage),
          ),
        ],
        child: const MaterialApp(
          home: ResultsScreen(attemptId: 'a1', testId: 't1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(UserFacingError.offlineMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
  });
}
