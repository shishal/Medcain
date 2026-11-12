import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medico/features/catalog/domain/catalog_models.dart';
import 'package:medico/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/domain/user_profile.dart';
import 'package:medico/features/profile/presentation/widgets/academic_editor.dart';

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

void main() {
  testWidgets(
    'university picker only lists universities in the selected state',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            universitiesProvider.overrideWith(
              (ref) async => const [_kuhs, _rguhs],
            ),
            mbbsPhasesProvider.overrideWith((ref) async => const []),
            collegesProvider.overrideWith((ref, id) async => const []),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AcademicEditor(
                  profile: UserProfile(
                    id: 'user-1',
                    fullName: 'Asha',
                    plan: PlanTier.pro,
                    createdAt: DateTime.utc(2026, 1, 1),
                    universityId: _kuhs.id,
                    mbbsPhaseId: 'p1',
                    onboardingCompletedAt: DateTime.utc(2026, 8, 1),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kerala'), findsOneWidget);
      expect(
        find.text('KUHS · Kerala University of Health Sciences'),
        findsOneWidget,
      );

      await tester.tap(find.text('State'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Karnataka'));
      await tester.pumpAndSettle();

      expect(find.text('Karnataka'), findsOneWidget);
      expect(find.text('Tap to choose'), findsOneWidget);

      await tester.tap(find.text('University'));
      await tester.pumpAndSettle();

      expect(
        find.text('RGUHS · Rajiv Gandhi University of Health Sciences'),
        findsOneWidget,
      );
      expect(
        find.text('KUHS · Kerala University of Health Sciences'),
        findsNothing,
      );
    },
  );
}
