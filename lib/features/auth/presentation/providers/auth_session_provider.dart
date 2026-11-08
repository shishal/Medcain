import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/result.dart';
import '../../data/auth_repository.dart';
import '../../domain/device_session.dart';

part 'auth_session_provider.g.dart';

/// Whether a Supabase session is active. Listens to auth state changes so the
/// router and splash screen stay in sync after login, logout, or app restart.
@Riverpod(keepAlive: true)
class AuthSession extends _$AuthSession {
  @override
  bool build() {
    final repository = ref.watch(authRepositoryProvider);

    final subscription = repository.authStateChanges.listen((event) {
      // Password sign-in emits signedIn before signIn() finishes claiming
      // this device. Publishing that session now rebuilds the router at
      // the splash screen, then the claim signs the user back out.
      if (event.event != AuthChangeEvent.signedIn) {
        state = event.session != null;
      }

      // Cold-start restore: bind this install before the user navigates.
      if (event.event == AuthChangeEvent.initialSession &&
          event.session != null) {
        // ignore: unawaited_futures
        repository.claimActiveDevice().then((claim) {
          if (claim case Success(:final value)
              when !value.ok || value.deviceLimit) {
            ref.read(deviceSessionNoticeProvider.notifier).setMessage(
              DeviceSessionMessages.deviceLimit,
            );
            repository.signOut();
          } else if (claim case Success(:final value)) {
            ref.read(deviceSessionNoticeProvider.notifier).setFromClaim(value);
          }
        });
      }

      // Refresh failed after another device revoked this session.
      if (event.event == AuthChangeEvent.signedOut &&
          event.signOutReason == SignOutReason.sessionExpired) {
        ref.read(deviceSessionNoticeProvider.notifier).setMessage(
          DeviceSessionMessages.signedInElsewhere,
        );
      }
    });
    ref.onDispose(subscription.cancel);

    return repository.isSignedIn;
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }

  /// Publish the session after [AuthRepository.signIn] / [signUp] finish.
  ///
  /// Those methods claim the device and may sign out before returning.
  /// [syncWithClient] then matches the router to whatever session is left.
  void syncWithClient() {
    state = ref.read(authRepositoryProvider).isSignedIn;
  }

  /// Force local sign-out when [assertActiveDevice] fails.
  Future<void> signOutBecauseOtherDevice() async {
    ref.read(deviceSessionNoticeProvider.notifier).setMessage(
      DeviceSessionMessages.signedInElsewhere,
    );
    await ref.read(authRepositoryProvider).signOut();
  }
}

/// One-shot banner/snackbar text (kicked device or plan suspension).
@Riverpod(keepAlive: true)
class DeviceSessionNotice extends _$DeviceSessionNotice {
  @override
  String? build() => null;

  void setMessage(String message) => state = message;

  void setFromClaim(ClaimActiveDeviceResult claim) {
    // Only the claim that crossed the 3rd-device threshold — not every login
    // while already suspended.
    if (claim.justSuspended) {
      state = DeviceSessionMessages.planSuspended;
    }
  }

  void clear() => state = null;
}
