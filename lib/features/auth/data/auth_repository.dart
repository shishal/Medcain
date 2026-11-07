import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../domain/auth_failure.dart';
import '../domain/device_session.dart';
import 'device_id_store.dart';

part 'auth_repository.g.dart';

/// Talks to Supabase Auth — presentation never calls the client directly.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  bool get isSignedIn => _client.auth.currentSession != null;

  /// Prefill only — checkout still requires a password on the web page.
  String? get currentEmail => _client.auth.currentUser?.email;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Null [ClaimActiveDeviceResult] when email confirmation is required (no session yet).
  Future<Result<ClaimActiveDeviceResult?>> signUp({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signUp(email: email, password: password);
      if (_client.auth.currentSession == null) {
        return const Success(null);
      }
      final claim = await claimActiveDevice();
      switch (claim) {
        case Success(:final value):
          if (!value.ok || value.deviceLimit) {
            await _client.auth.signOut(scope: SignOutScope.local);
            return const Failure(DeviceSessionMessages.deviceLimit);
          }
          return Success(value);
        case Failure(:final message):
          await _client.auth.signOut(scope: SignOutScope.local);
          return Failure(message);
      }
    } on AuthException catch (e) {
      return Failure(AuthFailure.fromException(e));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  Future<Result<ClaimActiveDeviceResult>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      final claim = await claimActiveDevice();
      switch (claim) {
        case Success(:final value):
          if (!value.ok || value.deviceLimit) {
            await _client.auth.signOut(scope: SignOutScope.local);
            return const Failure(DeviceSessionMessages.deviceLimit);
          }
          return Success(value);
        case Failure(:final message):
          await _client.auth.signOut(scope: SignOutScope.local);
          return Failure(message);
      }
    } on AuthException catch (e) {
      return Failure(AuthFailure.fromException(e));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  Future<Result<void>> signOut() async {
    try {
      // Local only so we don't revoke the *other* device that just claimed.
      await _client.auth.signOut(scope: SignOutScope.local);
      return const Success(null);
    } on AuthException catch (e) {
      return Failure(AuthFailure.fromException(e));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not sign out. Please try again.',
        ),
      );
    }
  }

  /// Registers this install when the plan has a free device slot.
  Future<Result<ClaimActiveDeviceResult>> claimActiveDevice() async {
    if (_client.auth.currentSession == null) {
      return const Failure('Not signed in.');
    }

    try {
      final deviceId = await getOrCreateDeviceId();
      final raw = await _client.rpc(
        RpcFunctions.claimActiveDevice,
        params: {DeviceSessionParams.deviceId: deviceId},
      );

      if (raw is! Map) {
        return const Failure('Could not register this device. Please try again.');
      }

      return Success(
        ClaimActiveDeviceResult.fromJson(Map<String, dynamic>.from(raw)),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not register this device. Please try again.',
        ),
      );
    }
  }

  /// Whether [profiles.active_device_id] still matches this install.
  Future<Result<bool>> assertActiveDevice() async {
    if (_client.auth.currentSession == null) {
      return const Success(false);
    }

    try {
      final deviceId = await getOrCreateDeviceId();
      final raw = await _client.rpc(
        RpcFunctions.assertActiveDevice,
        params: {DeviceSessionParams.deviceId: deviceId},
      );

      if (raw is! bool) {
        return const Failure('Could not verify this device. Please try again.');
      }

      return Success(raw);
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not verify this device. Please try again.',
        ),
      );
    }
  }
}

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
}
