// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_session_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether a Supabase session is active. Listens to auth state changes so the
/// router and splash screen stay in sync after login, logout, or app restart.

@ProviderFor(AuthSession)
final authSessionProvider = AuthSessionProvider._();

/// Whether a Supabase session is active. Listens to auth state changes so the
/// router and splash screen stay in sync after login, logout, or app restart.
final class AuthSessionProvider extends $NotifierProvider<AuthSession, bool> {
  /// Whether a Supabase session is active. Listens to auth state changes so the
  /// router and splash screen stay in sync after login, logout, or app restart.
  AuthSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authSessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authSessionHash();

  @$internal
  @override
  AuthSession create() => AuthSession();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$authSessionHash() => r'0af49d02d710d41c2c01b99ddc2ad49315cb7175';

/// Whether a Supabase session is active. Listens to auth state changes so the
/// router and splash screen stay in sync after login, logout, or app restart.

abstract class _$AuthSession extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// One-shot banner/snackbar text (kicked device or plan suspension).

@ProviderFor(DeviceSessionNotice)
final deviceSessionNoticeProvider = DeviceSessionNoticeProvider._();

/// One-shot banner/snackbar text (kicked device or plan suspension).
final class DeviceSessionNoticeProvider
    extends $NotifierProvider<DeviceSessionNotice, String?> {
  /// One-shot banner/snackbar text (kicked device or plan suspension).
  DeviceSessionNoticeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceSessionNoticeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceSessionNoticeHash();

  @$internal
  @override
  DeviceSessionNotice create() => DeviceSessionNotice();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$deviceSessionNoticeHash() =>
    r'2b833b18ccc9e71de134da542f78417187946505';

/// One-shot banner/snackbar text (kicked device or plan suspension).

abstract class _$DeviceSessionNotice extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
