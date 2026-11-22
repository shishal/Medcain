import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/admin/presentation/widgets/admin_student_preview_overlay.dart';
import 'features/app_update/presentation/force_update_gate.dart';
import 'features/auth/presentation/widgets/device_session_guard.dart';
import 'features/notifications/presentation/providers/broadcast_push_provider.dart';
import 'features/notifications/presentation/widgets/push_open_host.dart';
import 'features/security/presentation/widgets/app_screenshot_lock.dart';
import 'features/security/presentation/widgets/developer_mode_lock.dart';

class MedicoApp extends StatelessWidget {
  const MedicoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The update gate sits outside the router so a required update never
    // mounts Home, practice, or admin. Screenshot blocking stays outside
    // both locks so FLAG_SECURE remains on while a lock screen is showing.
    return const DeviceSessionGuard(
      child: AppScreenshotLock(
        child: ForceUpdateGate(child: DeveloperModeLock(child: _RoutedApp())),
      ),
    );
  }
}

class _RoutedApp extends ConsumerWidget {
  const _RoutedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Nobody else reads this. Watching it is what subscribes the phone
    // to the broadcast topic after sign-in.
    ref.watch(broadcastPushProvider);

    return MaterialApp.router(
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
          child: AdminStudentPreviewOverlay(
            child: PushOpenHost(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}
