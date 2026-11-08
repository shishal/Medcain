import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../domain/auth_failure.dart';
import '../domain/device_session.dart';
import '../domain/whatsapp_challenge.dart';
import '../domain/whatsapp_phone.dart';
import 'device_id_store.dart';

part 'auth_repository.g.dart';

/// Talks to Supabase Auth — presentation never calls the client directly.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  bool get isSignedIn => _client.auth.currentSession != null;

  /// Real email only. WhatsApp accounts use an internal mailbox students
  /// never see; [currentPhone] is their identifier.
  String? get currentEmail {
    final email = _client.auth.currentUser?.email;
    if (email == null || isSyntheticAuthEmail(email)) return null;
    return email;
  }

  String? get currentPhone => _client.auth.currentUser?.phone;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Asks the server for a wa.me link. Does not sign in yet.
  Future<Result<WhatsAppChallenge>> startWhatsAppSignIn({
    required String phone,
  }) async {
    try {
      final response = await _client.functions.invoke(
        EdgeFunctions.whatsappAuthStart,
        body: {'phone': phone},
      );
      final data = _asMap(response.data);
      final challenge = WhatsAppChallenge.tryParse(data);
      final uri = challenge == null ? null : Uri.tryParse(challenge.waUrl);
      if (challenge == null ||
          uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'wa.me') {
        return const Failure(
          'Could not start WhatsApp sign-in. Please try again.',
        );
      }
      return Success(challenge);
    } on FunctionException catch (error) {
      return Failure(
        _functionMessage(
          error,
          'Could not start WhatsApp sign-in. Please try again.',
        ),
      );
    } catch (error) {
      return Failure(
        UserFacingError.from(
          error,
          fallback: 'Could not start WhatsApp sign-in. Please try again.',
        ),
      );
    }
  }

  /// Null while the WhatsApp message has not arrived yet.
  /// A session is claimed onto this install the moment it is ready.
  Future<Result<ClaimActiveDeviceResult?>> finishWhatsAppSignIn({
    required String challengeId,
    required String secret,
  }) async {
    try {
      final response = await _client.functions.invoke(
        EdgeFunctions.whatsappAuthStatus,
        body: {'challenge_id': challengeId, 'secret': secret},
      );
      final data = _asMap(response.data);
      final status = data?['status'];
      if (status == 'pending') return const Success(null);
      if (status != 'ready') {
        return Failure(
          _stringField(data, 'error') ??
              'Could not finish sign-in. Please try again.',
        );
      }

      final refresh = data?['refresh_token'];
      if (refresh is! String || refresh.isEmpty) {
        return const Failure('Could not finish sign-in. Please try again.');
      }

      // setSession exchanges that refresh token for a stored Supabase
      // session. The WhatsApp secret is not a password.
      await _client.auth.setSession(refresh);
      return await _claimOrSignOut();
    } on FunctionException catch (error) {
      return Failure(
        _functionMessage(error, 'Could not finish sign-in. Please try again.'),
      );
    } on AuthException catch (error) {
      return Failure(AuthFailure.fromException(error));
    } catch (error) {
      return Failure(
        UserFacingError.from(
          error,
          fallback: 'Could not finish sign-in. Please try again.',
        ),
      );
    }
  }

  Future<Result<ClaimActiveDeviceResult>> _claimOrSignOut() async {
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

  Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  String? _stringField(Map<String, dynamic>? data, String key) {
    final value = data?[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 200) return null;
    return trimmed;
  }

  String _functionMessage(FunctionException error, String fallback) {
    if (UserFacingError.looksOffline(error)) {
      return UserFacingError.offlineMessage;
    }
    final details = error.details;
    if (details is Map) {
      return _stringField(Map<String, dynamic>.from(details), 'error') ??
          fallback;
    }
    if (details is String) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map) {
          return _stringField(Map<String, dynamic>.from(decoded), 'error') ??
              fallback;
        }
      } on FormatException {
        return fallback;
      }
    }
    return fallback;
  }
}

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
}
