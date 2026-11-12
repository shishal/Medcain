import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medico/features/catalog/domain/catalog_models.dart';
import 'package:medico/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:medico/features/onboarding/presentation/screens/onboarding_screen.dart';

const _kuhs = University(
  id: 'u-kuhs',
  code: 'KUHS',
  name: 'Kerala University of Health Sciences',
  state: 'Kerala',
  slug: 'kuhs',
);

const _rguhs = University(
  id: 'u-rguhs',
  code: 'RGUHS',
  name: 'Rajiv Gandhi University of Health Sciences',
  state: 'Karnataka',
  slug: 'rguhs',
);

const _phase1 = MbbsPhase(
  id: 'p1',
  code: 'phase1',
  name: '1st year',
  displayOrder: 1,
);

/// Docci’s bounce animation never settles, so we pump a fixed duration.
Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await _pumpUi(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('state step filters the university list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          universitiesProvider.overrideWith(
            (ref) async => const [_kuhs, _rguhs],
          ),
          mbbsPhasesProvider.overrideWith((ref) async => const [_phase1]),
          collegesProvider.overrideWith((ref, id) async => const []),
        ],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await _pumpUi(tester);

    await _next(tester);

    await tester.enterText(find.byType(TextField), 'Asha');
    await _next(tester);

    await tester.tap(find.text('1st year'));
    await _pumpUi(tester);
    await _next(tester);

    expect(find.text('Step 4 of 5'), findsOneWidget);
    await _next(tester);
    expect(find.text('Pick your state.'), findsOneWidget);

    await tester.tap(find.text('State'));
    await _pumpUi(tester);
    await tester.tap(find.text('Kerala'));
    await _pumpUi(tester);
    await _next(tester);

    expect(find.text('Step 5 of 5'), findsOneWidget);

    await tester.tap(find.text('University'));
    await _pumpUi(tester);

    expect(
      find.text('KUHS · Kerala University of Health Sciences'),
      findsOneWidget,
    );
    expect(
      find.text('RGUHS · Rajiv Gandhi University of Health Sciences'),
      findsNothing,
    );
  });
}
