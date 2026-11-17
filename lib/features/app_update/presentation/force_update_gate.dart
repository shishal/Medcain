import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../data/app_update_platform.dart';
import '../data/app_update_repository.dart';
import '../domain/app_update_policy.dart';
import 'force_update_screen.dart';

/// Hides [child] on Android until we know this build is allowed.
///
/// The router is not mounted while the check is in flight or while an
/// update is required, so a restored route cannot paint first. Coming back
/// to the foreground checks again (the admin may have raised or cleared
/// the minimum while the app was in the background).
class ForceUpdateGate extends ConsumerStatefulWidget {
  const ForceUpdateGate({
    required this.child,
    this.enforces,
    this.loadVerdict,
    super.key,
  });

  final Widget child;

  /// Null uses [appUpdateEnforced] (Android only). Tests pass a value.
  final bool? enforces;

  /// Null loads the rule from Supabase. Tests pass a fixed verdict.
  final Future<AppUpdateVerdict> Function()? loadVerdict;

  @override
  ConsumerState<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends ConsumerState<ForceUpdateGate>
    with WidgetsBindingObserver {
  /// False until the first check on a platform that enforces the rule.
  var _ready = false;
  AppUpdateVerdict _verdict = AppUpdateVerdict.allowed;

  bool get _enforces => widget.enforces ?? appUpdateEnforced;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_enforces) {
      _ready = true;
      return;
    }
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _enforces) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    final load =
        widget.loadVerdict ??
        () => ref.read(appUpdateRepositoryProvider).evaluate();
    AppUpdateVerdict verdict;
    try {
      verdict = await load();
    } catch (_) {
      // A thrown check must not unlock a phone that was already blocked.
      if (_verdict.blocked) return;
      verdict = AppUpdateVerdict.allowed;
    }
    if (!mounted) return;
    setState(() {
      _verdict = verdict;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      final brightness = MediaQueryData.fromView(View.of(context))
          .platformBrightness;
      return ColoredBox(color: AppTheme.splashCanvasFor(brightness));
    }
    if (_verdict.blocked) {
      final themeMode = ref.watch(themeModeProvider);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: ForceUpdateScreen(
          requiredVersionName: _verdict.requiredVersionName,
        ),
      );
    }
    return widget.child;
  }
}
