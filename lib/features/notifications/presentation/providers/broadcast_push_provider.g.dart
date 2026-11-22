// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'broadcast_push_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(broadcastPushController)
final broadcastPushControllerProvider = BroadcastPushControllerProvider._();

final class BroadcastPushControllerProvider
    extends
        $FunctionalProvider<
          BroadcastPushController,
          BroadcastPushController,
          BroadcastPushController
        >
    with $Provider<BroadcastPushController> {
  BroadcastPushControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'broadcastPushControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$broadcastPushControllerHash();

  @$internal
  @override
  $ProviderElement<BroadcastPushController> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BroadcastPushController create(Ref ref) {
    return broadcastPushController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BroadcastPushController value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BroadcastPushController>(value),
    );
  }
}

String _$broadcastPushControllerHash() =>
    r'b5fe68bee592a8c6b26268206f1deb993fb3e1a2';

/// Path from a notification tap, opened once the student is past splash.

@ProviderFor(PendingAnnouncementPath)
final pendingAnnouncementPathProvider = PendingAnnouncementPathProvider._();

/// Path from a notification tap, opened once the student is past splash.
final class PendingAnnouncementPathProvider
    extends $NotifierProvider<PendingAnnouncementPath, String?> {
  /// Path from a notification tap, opened once the student is past splash.
  PendingAnnouncementPathProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingAnnouncementPathProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingAnnouncementPathHash();

  @$internal
  @override
  PendingAnnouncementPath create() => PendingAnnouncementPath();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$pendingAnnouncementPathHash() =>
    r'b04659d9f94aaf0217e9bbc89bca75f8350276ba';

/// Path from a notification tap, opened once the student is past splash.

abstract class _$PendingAnnouncementPath extends $Notifier<String?> {
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

/// Keeps this install on the broadcast topic while a session exists.

@ProviderFor(broadcastPush)
final broadcastPushProvider = BroadcastPushProvider._();

/// Keeps this install on the broadcast topic while a session exists.

final class BroadcastPushProvider extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Keeps this install on the broadcast topic while a session exists.
  BroadcastPushProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'broadcastPushProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$broadcastPushHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return broadcastPush(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$broadcastPushHash() => r'600a5d5e2c9bfff5e157fbdc9966e7429a53d02b';
