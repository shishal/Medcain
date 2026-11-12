import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/screenshot_protection.dart';

/// Keeps capture blocking on for the whole process.
///
/// [ContentCaptureGuard] used to call [ScreenshotProtection.release] when
/// leaving the player, which turned Android screenshots back on for PYQ
/// screens. This widget holds the first acquire so nested guards can come
/// and go without calling `screenshotOn()`.
class AppScreenshotLock extends ConsumerStatefulWidget {
  const AppScreenshotLock({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppScreenshotLock> createState() => _AppScreenshotLockState();
}

class _AppScreenshotLockState extends ConsumerState<AppScreenshotLock> {
  ScreenshotProtection? _protection;
  var _acquired = false;

  @override
  void initState() {
    super.initState();
    _protection = ref.read(screenshotProtectionProvider);
    unawaited(_arm());
  }

  Future<void> _arm() async {
    await _protection?.acquire();
    _acquired = true;
  }

  @override
  void dispose() {
    if (_acquired) {
      unawaited(_protection?.release());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(screenshotProtectionProvider);
    return widget.child;
  }
}
