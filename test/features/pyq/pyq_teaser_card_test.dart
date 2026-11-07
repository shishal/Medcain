import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medico/core/utils/result.dart';
import 'package:medico/features/bookmarks/presentation/providers/bookmarks_provider.dart';
import 'package:medico/features/practice/domain/practice_enums.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/presentation/providers/current_plan_provider.dart';
import 'package:medico/features/pyq/domain/pyq_models.dart';
import 'package:medico/features/pyq/presentation/widgets/pyq_teaser_card.dart';

PyqTeaser _teaser({
  QuestionPriority priority = QuestionPriority.should,
  String text = 'Describe the femoral triangle.',
  int appearanceCount = 1,
  num? marks = 10,
  bool hasDirectAnswer = false,
  bool hasExplanation = false,
  PlanTier requiredPlan = PlanTier.free,
  String? textbookLine,
}) {
  return PyqTeaser(
    id: 'q1',
    questionText: text,
    marks: marks,
    requiredPlan: requiredPlan,
    appearanceCount: appearanceCount,
    kind: 'pyq_theory',
    priority: priority,
    appearanceYears: const [2024],
    paperNames: const ['Paper I'],
    textbookLine: textbookLine,
    hasDirectAnswer: hasDirectAnswer,
    hasExplanation: hasExplanation,
  );
}

Future<void> _pump(
  WidgetTester tester,
  PyqTeaser teaser, {
  PlanTier plan = PlanTier.free,
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
        currentPlanProvider.overrideWith((ref) async => plan),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PyqTeaserCard(teaser: teaser, index: 0, onTap: onTap),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hides the priority chip for the default Should', (tester) async {
    await _pump(tester, _teaser());

    expect(find.text('Should'), findsNothing);
    expect(find.text('Essay'), findsOneWidget);
    expect(find.text('10 marks'), findsOneWidget);
    expect(find.text('Answer available'), findsNothing);
    expect(find.text('Solution available'), findsNothing);
  });

  testWidgets('shows answer and solution chips only when content exists', (
    tester,
  ) async {
    await _pump(tester, _teaser(hasDirectAnswer: true));
    expect(find.text('Answer available'), findsOneWidget);
    expect(find.text('Solution available'), findsNothing);

    await _pump(tester, _teaser(hasExplanation: true));
    expect(find.text('Answer available'), findsNothing);
    expect(find.text('Solution available'), findsOneWidget);
  });

  testWidgets('shows a chip for a deliberate Must or Could', (tester) async {
    await _pump(tester, _teaser(priority: QuestionPriority.must));
    expect(find.text('Must'), findsOneWidget);

    await _pump(tester, _teaser(priority: QuestionPriority.could));
    expect(find.text('Could'), findsOneWidget);
  });

  testWidgets('High yield only appears from two appearances', (tester) async {
    await _pump(tester, _teaser());
    expect(find.text('High yield'), findsNothing);
    expect(find.textContaining('asked'), findsNothing);

    await _pump(tester, _teaser(appearanceCount: 3));
    expect(find.text('High yield'), findsOneWidget);
    expect(find.textContaining('asked 3×'), findsOneWidget);
  });

  testWidgets('truncates a long stem so an outline stays scannable', (
    tester,
  ) async {
    await _pump(
      tester,
      _teaser(
        text: List.filled(
          40,
          'Describe the gross anatomy and relations in detail.',
        ).join(' '),
      ),
    );

    final stem = tester.widget<Text>(find.textContaining('gross anatomy'));
    expect(stem.maxLines, 3);
    expect(stem.overflow, TextOverflow.ellipsis);
  });

  testWidgets('a free question shows a Free tag and opens', (tester) async {
    var taps = 0;
    await _pump(tester, _teaser(), onTap: () => taps++);

    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Describe the femoral triangle.'), findsOneWidget);

    await tester.tap(find.text('Describe the femoral triangle.'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a free plan masks a Pro stem and does not open it', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      _teaser(
        text: 'Write an essay on myocardial infarction.',
        requiredPlan: PlanTier.pro,
        textbookLine: 'Harrison p. 12',
        hasDirectAnswer: true,
      ),
      onTap: () => taps++,
    );

    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Write an essay on myocardial infarction.'), findsNothing);
    expect(find.text('Harrison p. 12'), findsNothing);
    expect(find.bySemanticsLabel('Question text hidden'), findsOneWidget);
    expect(find.text('Answer available'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Question text hidden'));
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  testWidgets('Pro can read a Pro stem and open it', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      _teaser(
        text: 'Write an essay on myocardial infarction.',
        requiredPlan: PlanTier.pro,
      ),
      plan: PlanTier.pro,
      onTap: () => taps++,
    );

    expect(find.text('Pro'), findsOneWidget);
    expect(
      find.text('Write an essay on myocardial infarction.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Write an essay on myocardial infarction.'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}

class _StubBookmarkedIds extends BookmarkedIds {
  @override
  Future<Set<String>> build() async => {};

  @override
  Future<Result<void>> toggle(String questionId) async => const Success(null);
}
