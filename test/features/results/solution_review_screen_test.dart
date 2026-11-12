import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/utils/result.dart';
import 'package:medico/core/utils/user_facing_error.dart';
import 'package:medico/features/bookmarks/presentation/providers/bookmarks_provider.dart';
import 'package:medico/features/practice/domain/practice_enums.dart';
import 'package:medico/features/results/domain/attempt_review.dart';
import 'package:medico/features/results/presentation/providers/attempt_review_provider.dart';
import 'package:medico/features/results/presentation/screens/solution_review_screen.dart';
import 'package:medico/features/results/presentation/widgets/review_question_view.dart';
import 'package:medico/features/security/data/screenshot_protection.dart';
import 'package:medico/features/security/domain/capture_event.dart';
import 'package:medico/features/security/presentation/providers/watermark_label_provider.dart';
import 'package:medico/features/tests/domain/player_question.dart';
import 'package:medico/features/tests/domain/question_option.dart';

const _explanation = 'Because mitochondria produce ATP.';

PlayerQuestion _question({
  required String id,
  required String text,
  QuestionOption correct = QuestionOption.a,
}) {
  return PlayerQuestion(
    id: id,
    orderIndex: 0,
    sectionNumber: 1,
    questionText: text,
    optionA: 'Mitochondria',
    optionB: 'Ribosome',
    optionC: 'Golgi',
    optionD: 'Nucleus',
    correctOption: correct,
    explanationText: _explanation,
  );
}

ReviewItem _item({
  required int number,
  required PlayerQuestion? question,
  ExplanationLevel level = ExplanationLevel.full,
  QuestionOption? selected = QuestionOption.b,
}) {
  return ReviewItem(
    questionId: question?.id ?? 'locked-$number',
    questionNumber: number,
    explanationLevel: level,
    selectedOption: selected,
    question: question,
  );
}

Future<void> _pumpView(WidgetTester tester, ReviewItem item) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ReviewQuestionView(item: item)),
    ),
  );
}

void main() {
  testWidgets('shows student answer, correct answer, and explanation', (
    tester,
  ) async {
    await _pumpView(
      tester,
      _item(
        number: 1,
        question: _question(id: 'q1', text: 'Which organelle produces ATP?'),
      ),
    );

    expect(find.text('Which organelle produces ATP?'), findsOneWidget);
    expect(find.text('Incorrect'), findsOneWidget);
    expect(find.text('Your answer: B'), findsOneWidget);
    expect(find.text('Correct answer: A'), findsOneWidget);
    expect(find.text(_explanation, findRichText: true), findsOneWidget);
    expect(find.text('Mitochondria'), findsOneWidget);
    expect(find.text('Ribosome'), findsOneWidget);
  });

  testWidgets('answer_only never renders explanation text', (tester) async {
    await _pumpView(
      tester,
      _item(
        number: 1,
        level: ExplanationLevel.answerOnly,
        question: _question(id: 'q1', text: 'Which organelle produces ATP?'),
      ),
    );

    expect(find.text('Correct answer: A'), findsOneWidget);
    expect(find.text(_explanation, findRichText: true), findsNothing);
  });

  testWidgets('plan-locked question fails gracefully', (tester) async {
    await _pumpView(tester, _item(number: 1, question: null));

    expect(
      find.text('This question is not available on your current plan.'),
      findsOneWidget,
    );
    expect(find.text('Upgrade'), findsOneWidget);
    expect(find.text(_explanation, findRichText: true), findsNothing);
    expect(find.text('Which organelle produces ATP?'), findsNothing);
  });

  testWidgets('palette and next move between questions', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final review = AttemptReview(
      attemptId: 'a1',
      testId: 't1',
      testTitle: 'Mini Test',
      explanationLevel: ExplanationLevel.full,
      items: [
        _item(
          number: 1,
          question: _question(id: 'q1', text: 'First stem'),
        ),
        _item(
          number: 2,
          selected: QuestionOption.a,
          question: _question(id: 'q2', text: 'Second stem'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attemptReviewProvider.overrideWith((ref, id) => review),
          bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
          screenshotProtectionProvider.overrideWithValue(_NoOpProtection()),
          watermarkLabelProvider.overrideWithValue('ada@example.com'),
        ],
        child: const MaterialApp(home: SolutionReviewScreen(attemptId: 'a1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('First stem'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Second stem'), findsOneWidget);
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('bookmark icon toggles on the current review question', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final review = AttemptReview(
      attemptId: 'a1',
      testId: 't1',
      testTitle: 'Mini Test',
      explanationLevel: ExplanationLevel.full,
      items: [
        _item(
          number: 1,
          question: _question(id: 'q1', text: 'First stem'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attemptReviewProvider.overrideWith((ref, id) => review),
          bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
          screenshotProtectionProvider.overrideWithValue(_NoOpProtection()),
          watermarkLabelProvider.overrideWithValue('ada@example.com'),
        ],
        child: const MaterialApp(home: SolutionReviewScreen(attemptId: 'a1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Bookmark'), findsOneWidget);

    await tester.tap(find.byTooltip('Bookmark'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Remove bookmark'), findsOneWidget);
  });

  testWidgets('empty review shows an empty state', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const review = AttemptReview(
      attemptId: 'a1',
      testId: 't1',
      testTitle: 'Mini Test',
      explanationLevel: ExplanationLevel.full,
      items: [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attemptReviewProvider.overrideWith((ref, id) => review),
          bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
          screenshotProtectionProvider.overrideWithValue(_NoOpProtection()),
          watermarkLabelProvider.overrideWithValue('ada@example.com'),
        ],
        child: const MaterialApp(home: SolutionReviewScreen(attemptId: 'a1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No questions to review.'), findsOneWidget);
  });

  testWidgets('error state shows offline copy and Retry', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attemptReviewProvider.overrideWith(
            (ref, id) => throw Exception(UserFacingError.offlineMessage),
          ),
          bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
          screenshotProtectionProvider.overrideWithValue(_NoOpProtection()),
          watermarkLabelProvider.overrideWithValue('ada@example.com'),
        ],
        child: const MaterialApp(home: SolutionReviewScreen(attemptId: 'a1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(UserFacingError.offlineMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

class _StubBookmarkedIds extends BookmarkedIds {
  @override
  Future<Set<String>> build() async => {};

  @override
  Future<Result<void>> toggle(String questionId) async {
    final current = Set<String>.from(state.value ?? const <String>{});
    if (!current.add(questionId)) current.remove(questionId);
    state = AsyncData(current);
    return const Success(null);
  }
}

class _NoOpProtection implements ScreenshotProtection {
  @override
  Stream<CaptureEvent> get events => const Stream.empty();

  @override
  Future<void> acquire() async {}

  @override
  Future<void> release() async {}
}
