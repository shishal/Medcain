import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/auth/presentation/widgets/device_session_guard.dart';
import 'features/security/presentation/widgets/app_screenshot_lock.dart';
import 'features/security/presentation/widgets/developer_mode_lock.dart';

class MedicoApp extends ConsumerWidget {
  const MedicoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Screenshot blocking stays outside the developer-mode lock so
    // FLAG_SECURE remains on while the lock screen is showing.
    return DeviceSessionGuard(
      child: AppScreenshotLock(
        child: DeveloperModeLock(
          child: MaterialApp.router(
            title: 'MEDCAIN',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            routerConfig: router,
            // go_router and other packages still read the theme from
            // package:flutter/material.dart. This bridge copies it down.
            builder: (context, child) {
              // ignore: deprecated_member_use
              return MaterialUiCompatibilityBridge(
                child: child ?? const SizedBox.shrink(),
              );
            },
          ),
        ),
      ),
    );
  }
}
