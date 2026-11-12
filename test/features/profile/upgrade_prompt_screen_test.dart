import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/profile/data/checkout_env.dart';
import 'package:medico/features/profile/data/checkout_launcher.dart';
import 'package:medico/features/profile/domain/plan_offer.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/presentation/providers/public_plans_provider.dart';
import 'package:medico/features/profile/presentation/screens/upgrade_prompt_screen.dart';

PlanOffer _offer({
  required String id,
  required String code,
  required String name,
  required int amountPaise,
  required List<String> benefits,
  int? durationMonths,
  String? durationLabel,
}) {
  return PlanOffer(
    id: id,
    code: code,
    name: name,
    tagline: name == 'Free'
        ? 'Questions marked as a free preview'
        : 'The full bank',
    benefits: benefits,
    amountPaise: amountPaise,
    durationMonths: durationMonths,
    durationLabel: durationLabel,
    maxRegisteredDevices: code == 'elite' ? 2 : 1,
    isPublic: true,
    isActive: true,
    sortOrder: 0,
    contentDepth: 'explanation',
    accessMode: code == 'free' ? 'preview_only' : 'filtered',
    allowPractice: true,
    allowTutorMode: true,
    allowExamMode: true,
    allowTimerToggle: code != 'free',
    allowTagFilter: code != 'free',
    allowDifficultyFilter: true,
    allowNegativeMarkingToggle: code != 'free',
  );
}

final _plans = [
  _offer(
    id: 'free-id',
    code: 'free',
    name: 'Free',
    amountPaise: 0,
    benefits: const ['Free preview questions', '1 registered device'],
  ),
  _offer(
    id: 'pro-id',
    code: 'pro',
    name: 'Pro',
    amountPaise: 149900,
    durationMonths: 12,
    durationLabel: '1 year',
    benefits: const [
      'All questions, all years, all subjects',
      '1 registered device',
    ],
  ),
  _offer(
    id: 'elite-id',
    code: 'elite',
    name: 'Elite',
    amountPaise: 299900,
    durationMonths: 12,
    durationLabel: '1 year',
    benefits: const [
      'All questions, all years, all subjects',
      '2 registered devices',
    ],
  ),
];

Future<void> _pumpUpgrade(
  WidgetTester tester, {
  required PlanTier requiredPlan,
  PlanOffer? current,
  required CheckoutLauncher launcher,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        publicPlansProvider.overrideWith((ref) async => _plans),
        effectivePlanProvider.overrideWith(
          (ref) async => current ?? _plans.first,
        ),
        checkoutLauncherProvider.overrideWithValue(launcher),
      ],
      child: MaterialApp(home: UpgradePromptScreen(requiredPlan: requiredPlan)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows Free, Pro, and Elite comparison without in-app purchase', (
    tester,
  ) async {
    await _pumpUpgrade(
      tester,
      requiredPlan: PlanTier.pro,
      launcher: CheckoutLauncher(
        checkoutUri: Uri.parse('https://checkout.test/pay'),
        launch: (_) async => true,
      ),
    );

    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Pro'), findsWidgets);
    expect(find.text('Elite'), findsWidgets);
    expect(find.text('All questions, all years, all subjects'), findsNWidgets(2));
    expect(find.text('1 registered device'), findsNWidgets(2));
    expect(find.text('2 registered devices'), findsOneWidget);
    expect(find.text('₹1499'), findsOneWidget);
    expect(find.text('₹2999'), findsOneWidget);

    expect(find.text('Purchase Pro'), findsOneWidget);
    expect(find.text('Purchase Elite'), findsOneWidget);
    expect(find.textContaining('Buy'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('Purchase is shown and does not open the browser by itself', (
    tester,
  ) async {
    expect(CheckoutEnv.webCheckoutEnabled, isTrue);

    final opened = <Uri>[];
    await _pumpUpgrade(
      tester,
      requiredPlan: PlanTier.elite,
      launcher: CheckoutLauncher(
        checkoutUri: Uri.parse('https://checkout.test/pay'),
        launch: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );

    expect(find.text('Purchase Elite'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('Free card has no checkout action', (tester) async {
    await _pumpUpgrade(
      tester,
      requiredPlan: PlanTier.pro,
      launcher: CheckoutLauncher(
        checkoutUri: Uri.parse('https://checkout.test/pay'),
        launch: (_) async => true,
      ),
    );

    expect(find.text('Purchase Free'), findsNothing);
  });

  testWidgets('current paid plan hides its own checkout button', (
    tester,
  ) async {
    await _pumpUpgrade(
      tester,
      requiredPlan: PlanTier.elite,
      current: _plans[1],
      launcher: CheckoutLauncher(
        checkoutUri: Uri.parse('https://checkout.test/pay'),
        launch: (_) async => true,
      ),
    );

    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Purchase Pro'), findsNothing);
    expect(find.text('Purchase Elite'), findsOneWidget);
  });
}
