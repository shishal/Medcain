import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../data/developer_mode_monitor.dart';
import '../screens/developer_mode_blocked_screen.dart';

/// Hides [child] while Android Developer options or USB debugging is on.
///
/// [child] is not mounted in that state, so question text is not in the
/// widget tree (a layout inspector could otherwise read it). The first
/// frame stays blank until the native check returns, so a restored
/// question route cannot paint first.
///
/// Coming back to the foreground checks again. The native side also
/// watches the setting and covers the window immediately, then this
/// widget swaps in the lock screen.
class DeveloperModeLock extends ConsumerStatefulWidget {
  const DeveloperModeLock({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DeveloperModeLock> createState() => _DeveloperModeLockState();
}

class _DeveloperModeLockState extends ConsumerState<DeveloperModeLock>
    with WidgetsBindingObserver {
  /// Null until the first check. False shows [child]. True shows the lock.
  bool? _blocked;
  StreamSubscription<bool>? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final monitor = ref.read(developerModeMonitorProvider);
    // Debug and iOS do not enforce, so the app can paint on the first frame.
    _blocked = monitor.enforces ? null : false;
    _subscription = monitor.watch().listen(
      _setBlocked,
      onError: (_) {
        // A dead event stream on Android must not leave content up.
        if (monitor.enforces) _setBlocked(true);
      },
    );
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `resumed` means the app is in the foreground again. The student
    // may have turned Developer options on while it was backgrounded.
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final blocked = await ref.read(developerModeMonitorProvider).isEnabled();
    _setBlocked(blocked);
  }

  void _setBlocked(bool blocked) {
    if (!mounted || _blocked == blocked) return;
    setState(() => _blocked = blocked);
    if (blocked) _scheduleShieldRelease();
  }

  /// Drops the native cover only after the lock screen has been painted,
  /// so removing it cannot reveal a question frame underneath.
  void _scheduleShieldRelease() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _blocked != true) return;
      unawaited(ref.read(developerModeMonitorProvider).releaseShield());
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(developerModeMonitorProvider);
    final blocked = _blocked;
    if (blocked == null) {
      final brightness = MediaQueryData.fromView(View.of(context))
          .platformBrightness;
      return ColoredBox(color: AppTheme.splashCanvasFor(brightness));
    }
    if (blocked) {
      final themeMode = ref.watch(themeModeProvider);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: const DeveloperModeBlockedScreen(),
      );
    }
    return widget.child;
  }
}
