import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medico/core/router/app_routes.dart';
import 'package:medico/core/theme/app_theme.dart';
import 'package:medico/features/auth/presentation/providers/auth_session_provider.dart';
import 'package:medico/features/auth/presentation/screens/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches splash branding', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(
      initialLocation: AppRoutes.splash,
      routes: [
        GoRoute(
          path: AppRoutes.splash,
          builder: (_, _) => const SplashScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWithValue(false)],
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    );

    expect(find.text('MEDCAIN'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 1300));
  });
}
