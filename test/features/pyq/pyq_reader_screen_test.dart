import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medico/core/router/app_routes.dart';
import 'package:medico/core/utils/result.dart';
import 'package:medico/features/bookmarks/presentation/providers/bookmarks_provider.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/presentation/providers/current_plan_provider.dart';
import 'package:medico/features/pyq/data/pyq_repository.dart';
import 'package:medico/features/pyq/domain/pyq_models.dart';
import 'package:medico/features/pyq/presentation/providers/pyq_providers.dart';
import 'package:medico/features/pyq/presentation/screens/pyq_reader_screen.dart';
import 'package:medico/features/security/data/screenshot_protection.dart';
import 'package:medico/features/security/domain/capture_event.dart';
import 'package:medico/features/security/presentation/providers/watermark_label_provider.dart';

PyqTeaser _teaser({
  required String id,
  required String text,
  String kind = 'pyq_theory',
  num marks = 10,
  PlanTier requiredPlan = PlanTier.free,
}) {
  return PyqTeaser(
    id: id,
    questionText: text,
    marks: marks,
    requiredPlan: requiredPlan,
    appearanceCount: 1,
    kind: kind,
    appearanceYears: const [2024],
    paperNames: const ['Paper I'],
  );
}

PyqDetail _detail({
  required PyqTeaser teaser,
  String? sample,
  bool canReadSample = true,
  String? explanation,
  String? correctOption,
  String? optionA,
  String? optionB,
  List<TextbookCitation> textbooks = const [],
}) {
  return PyqDetail(
    teaser: teaser,
    appearances: const [ExamAppearance(year: 2024, paperName: 'Paper I')],
    textbookRefs: textbooks,
    lessonResources: const [],
    questionResources: const [],
    sampleAnswer: sample,
    canReadSample: canReadSample,
    questionLearnt: false,
    optionA: optionA,
    optionB: optionB,
    correctOption: correctOption,
    explanationText: explanation,
  );
}

Future<void> _pumpReader(
  WidgetTester tester, {
  required PyqDetail detail,
  PlanTier plan = PlanTier.pro,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});

  final router = GoRouter(
    initialLocation: AppRoutes.pyqPath(detail.teaser.id),
    routes: [
      GoRoute(
        path: AppRoutes.pyq,
        builder: (_, state) =>
            PyqReaderScreen(questionId: state.pathParameters['questionId']!),
      ),
      GoRoute(
        path: AppRoutes.upgrade,
        builder: (_, _) => const Text('Upgrade'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pyqDetailProvider.overrideWith((ref, id) async => detail),
        currentPlanProvider.overrideWith((ref) async => plan),
        bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
        screenshotProtectionProvider.overrideWithValue(_NoOpProtection()),
        watermarkLabelProvider.overrideWithValue('ada@example.com'),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reader starts with DA open; EX stays collapsed until tapped', (
    tester,
  ) async {
    await _pumpReader(
      tester,
      detail: _detail(
        teaser: _teaser(id: 'q1', text: 'Define jaundice.'),
        sample: 'Yellow discoloration of skin.',
        explanation: 'Bilirubin deposits in tissues.',
        textbooks: const [TextbookCitation(title: 'Harrison', page: 42)],
      ),
    );

    expect(find.text('Define jaundice.'), findsOneWidget);
    expect(find.text('Yellow discoloration of skin.'), findsOneWidget);
    expect(find.text('Bilirubin deposits in tissues.'), findsNothing);
    expect(find.textContaining('Harrison'), findsNothing);

    await tester.tap(find.text('EX'));
    await tester.pumpAndSettle();
    expect(find.text('Yellow discoloration of skin.'), findsNothing);
    expect(find.text('Bilirubin deposits in tissues.'), findsOneWidget);
    expect(find.textContaining('Harrison'), findsOneWidget);
  });

  testWidgets('free user sees a Pro lock on DA', (tester) async {
    await _pumpReader(
      tester,
      plan: PlanTier.free,
      detail: _detail(
        teaser: _teaser(id: 'q1', text: 'Define jaundice.'),
        sample: null,
        canReadSample: false,
        explanation: 'Hidden write-up.',
      ),
    );

    expect(find.text('Direct answer'), findsOneWidget);
    expect(find.text('Included with Pro'), findsOneWidget);

    await tester.tap(find.text('EX'));
    await tester.pumpAndSettle();
    expect(find.text('Hidden write-up.'), findsOneWidget);
  });

  testWidgets('MCQ DA highlights the key without putting it on EX', (
    tester,
  ) async {
    await _pumpReader(
      tester,
      detail: _detail(
        teaser: _teaser(
          id: 'm1',
          text: 'Which organelle produces ATP?',
          kind: 'mcq',
          marks: 1,
        ),
        sample: 'Mitochondria make ATP.',
        explanation: 'Oxidative phosphorylation.',
        correctOption: 'A',
        optionA: 'Mitochondria',
        optionB: 'Ribosome',
      ),
    );

    expect(find.text('A. Mitochondria'), findsOneWidget);
    expect(find.text('Answer: A'), findsOneWidget);
    // The key is marked on the option itself too, so colour is not the only
    // cue for a red-green colour-blind student.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.text('Mitochondria make ATP.'), findsOneWidget);
    expect(find.text('Oxidative phosphorylation.'), findsNothing);
  });

  testWidgets('a free plan cannot open a Pro question answer', (tester) async {
    await _pumpReader(
      tester,
      plan: PlanTier.free,
      detail: _detail(
        teaser: _teaser(
          id: 'q-pro',
          text: 'Describe compensated shock.',
          requiredPlan: PlanTier.pro,
        ),
        sample: 'Tachycardia with a normal blood pressure.',
        explanation: 'Sympathetic compensation.',
      ),
    );

    expect(find.text('Describe compensated shock.'), findsNothing);
    expect(
      find.text('Tachycardia with a normal blood pressure.'),
      findsNothing,
    );
    expect(find.text('Sympathetic compensation.'), findsNothing);
    expect(find.textContaining('included with Pro'), findsOneWidget);
  });

  testWidgets('floating text size enlarges the question and the answer', (
    tester,
  ) async {
    await _pumpReader(
      tester,
      detail: _detail(
        teaser: _teaser(
          id: 'm1',
          text: 'Which organelle produces ATP?',
          kind: 'mcq',
          marks: 1,
        ),
        sample: 'Mitochondria make ATP.',
        correctOption: 'A',
        optionA: 'Mitochondria',
        optionB: 'Ribosome',
      ),
    );

    double px(String text) {
      final rich = tester.widget<RichText>(
        find.text(text, findRichText: true),
      );
      return rich.textScaler.scale(14);
    }

    final questionBefore = px('Which organelle produces ATP?');
    final optionBefore = px('A. Mitochondria');
    final answerBefore = px('Mitochondria make ATP.');

    // One control for the page — not a second pair inside the answer card.
    expect(find.byIcon(Icons.text_increase), findsOneWidget);

    await tester.tap(find.byIcon(Icons.text_increase));
    await tester.pump();

    expect(px('Which organelle produces ATP?'), greaterThan(questionBefore));
    expect(px('A. Mitochondria'), greaterThan(optionBefore));
    expect(px('Mitochondria make ATP.'), greaterThan(answerBefore));
  });
}

class _StubBookmarkedIds extends BookmarkedIds {
  @override
  Future<Set<String>> build() async => {};

  @override
  Future<Result<void>> toggle(String questionId) async {
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
