import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medico/features/app_update/domain/app_update_policy.dart';
import 'package:medico/features/app_update/presentation/force_update_gate.dart';
import 'package:medico/features/app_update/presentation/force_update_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpGate(
    WidgetTester tester, {
    required bool enforces,
    required Future<AppUpdateVerdict> Function() loadVerdict,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ForceUpdateGate(
          enforces: enforces,
          loadVerdict: loadVerdict,
          child: const MaterialApp(home: Text('home')),
        ),
      ),
    );
  }

  testWidgets('shows the app when this platform does not enforce', (
    tester,
  ) async {
    await pumpGate(
      tester,
      enforces: false,
      loadVerdict: () async =>
          const AppUpdateVerdict(blocked: true, requiredVersionName: '9.0.0'),
    );

    expect(find.text('home'), findsOneWidget);
    expect(find.text(ForceUpdateScreen.title), findsNothing);
  });

  testWidgets('hides the app and offers the Play Store button when blocked', (
    tester,
  ) async {
    await pumpGate(
      tester,
      enforces: true,
      loadVerdict: () async =>
          const AppUpdateVerdict(blocked: true, requiredVersionName: '1.1.26'),
    );
    await tester.pump();

    expect(find.text('home'), findsNothing);
    expect(find.text(ForceUpdateScreen.title), findsOneWidget);
    expect(find.text('Version 1.1.26 or newer.'), findsOneWidget);
    expect(find.text(ForceUpdateScreen.buttonLabel), findsOneWidget);
  });

  testWidgets('shows the app when the installed build is allowed', (
    tester,
  ) async {
    await pumpGate(
      tester,
      enforces: true,
      loadVerdict: () async => AppUpdateVerdict.allowed,
    );
    await tester.pump();

    expect(find.text('home'), findsOneWidget);
    expect(find.text(ForceUpdateScreen.title), findsNothing);
  });

  testWidgets('the update button calls the handler', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ForceUpdateScreen(
          onUpdate: (_) async {
            taps++;
          },
        ),
      ),
    );

    await tester.tap(find.text(ForceUpdateScreen.buttonLabel));
    await tester.pump();

    expect(taps, 1);
  });
}
