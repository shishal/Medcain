import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/profile/data/checkout_env.dart';
import 'package:medico/features/profile/data/checkout_launcher.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/presentation/providers/current_plan_provider.dart';
import 'package:medico/features/profile/presentation/screens/upgrade_prompt_screen.dart';

Future<void> _pumpUpgrade(
  WidgetTester tester, {
  required PlanTier requiredPlan,
  PlanTier currentPlan = PlanTier.free,
  required CheckoutLauncher launcher,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentPlanProvider.overrideWith((ref) async => currentPlan),
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
    expect(find.text('1 registered device'), findsOneWidget);
    expect(find.text('2 registered devices'), findsOneWidget);

    expect(find.text('Purchase Pro'), findsOneWidget);
    expect(find.text('Purchase Elite'), findsOneWidget);
    expect(find.textContaining('Buy'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
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
      currentPlan: PlanTier.pro,
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
