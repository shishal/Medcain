import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/brand_assets.dart';
import '../../../../core/theme/brand_identity.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/brand_mark.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../../../../core/widgets/brand_pulse_loader.dart';
import '../../../../core/widgets/comic_mascot.dart';
import '../../data/auth_repository.dart';
import '../../domain/device_session.dart';
import '../providers/auth_session_provider.dart';

/// Brief branded splash; navigates to login or home based on auth session.
///
/// The ECG-M stays screen-center so it lines up with the native launch image
/// from flutter_native_splash. Docci and the wordmark fade in around it.
/// Canvas + mark follow the active theme (light paper / dark black).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final Animation<double> _markScale;
  late final Animation<double> _copyOpacity;
  late final Animation<double> _mascotOpacity;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _markScale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0, 0.5, curve: Curves.easeOutCubic),
      ),
    );
    _copyOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.28, 0.7, curve: Curves.easeOut),
    );
    _mascotOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.38, 0.9, curve: Curves.easeOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigateAway());
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Device claim and profile load. A hung database call must not keep
  /// the splash up after this.
  static const _startupWait = Duration(seconds: 8);

  Future<void> _navigateAway() async {
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;

    var isAuthenticated = ref.read(authSessionProvider);
    if (isAuthenticated) {
      final alreadyLeft = await _confirmDevice().timeout(
        _startupWait,
        onTimeout: () => false,
      );
      if (!mounted || alreadyLeft) return;
      isAuthenticated = ref.read(authSessionProvider);
    }

    if (!isAuthenticated) {
      context.go(AppRoutes.login);
      return;
    }

    // Admins skip the student home. A failed or slow profile still opens
    // Home; the router sends an admin on once the row arrives.
    var isAdmin = false;
    try {
      final profile = await ref
          .read(userProfileProvider.future)
          .timeout(_startupWait);
      isAdmin = profile?.isAdmin ?? false;
    } catch (_) {
      isAdmin = false;
    }
    if (!mounted) return;
    context.go(isAdmin ? AppRoutes.admin : AppRoutes.home);
  }

  /// Registers this phone. Returns true when login was already opened.
  Future<bool> _confirmDevice() async {
    final repo = ref.read(authRepositoryProvider);
    final claim = await repo.claimActiveDevice();
    if (!mounted) return true;

    if (claim case Success(:final value)) {
      if (!value.ok || value.deviceLimit) {
        ref.read(deviceSessionNoticeProvider.notifier).setMessage(
          DeviceSessionMessages.deviceLimit,
        );
        await ref.read(authSessionProvider.notifier).signOut();
        if (!mounted) return true;
        context.go(AppRoutes.loginWithReason(AppRoutes.loginReasonDeviceLimit));
        return true;
      }
      ref.read(deviceSessionNoticeProvider.notifier).setFromClaim(value);
    }

    final assertResult = await repo.assertActiveDevice();
    if (!mounted) return true;

    final stillActive = switch (assertResult) {
      Success(:final value) => value,
      Failure() => true, // don't lock out on a transient RPC failure
    };

    if (!stillActive) {
      await ref.read(authSessionProvider.notifier).signOutBecauseOtherDevice();
      if (!mounted) return true;
      context.go(AppRoutes.loginWithReason(AppRoutes.loginReasonOtherDevice));
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final comic = ComicColors.of(context);
    final canvas = AppTheme.splashCanvasFor(brightness);
    final onCanvas = dark ? Colors.white : comic.ink;
    final textTheme = Theme.of(context).textTheme;
    final gradient = dark
        ? const [
            Color(0xFF0A2A3D),
            AppTheme.splashCanvas,
            Color(0xFF000000),
          ]
        : [
            const Color(0xFFE8F4FC),
            canvas,
            const Color(0xFFE4E4E7),
          ];

    return Scaffold(
      backgroundColor: canvas,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.12),
            radius: 1.15,
            colors: gradient,
            stops: const [0.0, 0.48, 1.0],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _intro,
            builder: (context, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: const Alignment(0, -0.42),
                    child: Opacity(
                      opacity: _mascotOpacity.value,
                      child: const ComicMascot(
                        asset: BrandAssets.mascotWave,
                        size: 128,
                        heroTag: BrandAssets.mascotHeroTag,
                      ),
                    ),
                  ),
                  Center(
                    child: Transform.scale(
                      scale: _markScale.value,
                      child: const BrandMark(size: 88),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.38),
                    child: Opacity(
                      opacity: _copyOpacity.value,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            BrandIdentity.displayName,
                            style: textTheme.headlineMedium?.copyWith(
                              color: onCanvas,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            BrandIdentity.tagline,
                            textAlign: TextAlign.center,
                            style: textTheme.bodyLarge?.copyWith(
                              color: onCanvas.withValues(alpha: 0.82),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: Spacing.lg),
                          BrandPulseLoader(
                            color: dark
                                ? const Color(0xFF00AEEF)
                                : AppTheme.seedColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
