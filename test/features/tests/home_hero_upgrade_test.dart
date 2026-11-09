import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medico/core/router/app_routes.dart';
import 'package:medico/core/theme/app_theme.dart';
import 'package:medico/features/catalog/domain/catalog_models.dart';
import 'package:medico/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/domain/user_profile.dart';
import 'package:medico/features/profile/presentation/providers/user_profile_provider.dart';
import 'package:medico/features/progress/domain/progress_models.dart';
import 'package:medico/features/progress/presentation/providers/ug_home_providers.dart';
import 'package:medico/features/tests/presentation/widgets/home_hero_banner.dart';

class _Profile extends UserProfileNotifier {
  _Profile(this.plan);

  final PlanTier plan;

  @override
  Future<UserProfile?> build() async {
    return UserProfile(
      id: 'user-1',
      fullName: 'Asha Nair',
      plan: plan,
      createdAt: DateTime.utc(2026, 1, 1),
      mbbsPhaseId: 'p1',
      onboardingCompletedAt: DateTime.utc(2026, 8, 1),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GoRouter> pumpBanner(WidgetTester tester, PlanTier plan) async {
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const Scaffold(body: HomeHeroBanner()),
        ),
        GoRoute(
          path: AppRoutes.upgrade,
          builder: (_, _) => const Scaffold(body: Text('Plans screen')),
        ),
        GoRoute(
          path: AppRoutes.search,
          builder: (_, _) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: AppRoutes.notifications,
          builder: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith(() => _Profile(plan)),
          mbbsPhasesProvider.overrideWith(
            (ref) async => const [
              MbbsPhase(id: 'p1', code: 'Y1', name: '1st year', displayOrder: 1),
            ],
          ),
          universitiesProvider.overrideWith((ref) async => const []),
          studyProgressProvider.overrideWith(
            (ref) async => const StudyProgress(
              streak: 0,
              days7: [],
              days30: [],
              subjects: [],
            ),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return router;
  }

  testWidgets('free plan shows Upgrade beside the Free label', (tester) async {
    final router = await pumpBanner(tester, PlanTier.free);

    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);

    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.upgrade);
    expect(find.text('Plans screen'), findsOneWidget);
  });

  testWidgets('paid plan keeps the pill as a label', (tester) async {
    await pumpBanner(tester, PlanTier.pro);

    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Upgrade'), findsNothing);
  });
}
