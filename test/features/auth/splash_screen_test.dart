import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:medico/core/router/app_routes.dart';
import 'package:medico/core/theme/app_theme.dart';
import 'package:medico/core/theme/brand_assets.dart';
import 'package:medico/core/widgets/brand_pulse_loader.dart';
import 'package:medico/features/auth/presentation/providers/auth_session_provider.dart';
import 'package:medico/features/auth/presentation/screens/splash_screen.dart';

void main() {
  testWidgets('Splash shows brand mark on light canvas by default', (tester) async {
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
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.light,
          routerConfig: router,
        ),
      ),
    );

    expect(find.text('MEDCAIN'), findsOneWidget);
    expect(find.text('Drug of Choice for Exam Pain'), findsOneWidget);
    expect(find.byType(BrandPulseLoader), findsOneWidget);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTheme.splashCanvasLight);

    await tester.pump(const Duration(milliseconds: 1300));
  });

  testWidgets('Splash uses dark canvas in dark theme', (tester) async {
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
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          routerConfig: router,
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTheme.splashCanvas);
    expect(BrandAssets.markFor(Brightness.dark), BrandAssets.splashLogo);
    expect(BrandAssets.markFor(Brightness.light), BrandAssets.splashLogoLight);

    await tester.pump(const Duration(milliseconds: 1300));
  });
}
