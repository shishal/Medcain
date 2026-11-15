// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_session_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Player for one [testId]. Creates or resumes an `attempts` row, downloads
/// questions, and autosaves answers to a local JSON file (spec §4).
///
/// The countdown is derived from wall-clock elapsed time (spec §3). A 1s tick
/// only checks for expiry — remaining seconds are never written to disk.

@ProviderFor(PlayerSession)
final playerSessionProvider = PlayerSessionFamily._();

/// Player for one [testId]. Creates or resumes an `attempts` row, downloads
/// questions, and autosaves answers to a local JSON file (spec §4).
///
/// The countdown is derived from wall-clock elapsed time (spec §3). A 1s tick
/// only checks for expiry — remaining seconds are never written to disk.
final class PlayerSessionProvider
    extends $AsyncNotifierProvider<PlayerSession, PlayerSessionState> {
  /// Player for one [testId]. Creates or resumes an `attempts` row, downloads
  /// questions, and autosaves answers to a local JSON file (spec §4).
  ///
  /// The countdown is derived from wall-clock elapsed time (spec §3). A 1s tick
  /// only checks for expiry — remaining seconds are never written to disk.
  PlayerSessionProvider._({
    required PlayerSessionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'playerSessionProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$playerSessionHash();

  @override
  String toString() {
    return r'playerSessionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PlayerSession create() => PlayerSession();

  @override
  bool operator ==(Object other) {
    return other is PlayerSessionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$playerSessionHash() => r'b037e378c2898c749d89c87dbadbb93cb904af34';

/// Player for one [testId]. Creates or resumes an `attempts` row, downloads
/// questions, and autosaves answers to a local JSON file (spec §4).
///
/// The countdown is derived from wall-clock elapsed time (spec §3). A 1s tick
/// only checks for expiry — remaining seconds are never written to disk.

final class PlayerSessionFamily extends $Family
    with
        $ClassFamilyOverride<
          PlayerSession,
          AsyncValue<PlayerSessionState>,
          PlayerSessionState,
          FutureOr<PlayerSessionState>,
          String
        > {
  PlayerSessionFamily._()
    : super(
        retry: null,
        name: r'playerSessionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Player for one [testId]. Creates or resumes an `attempts` row, downloads
  /// questions, and autosaves answers to a local JSON file (spec §4).
  ///
  /// The countdown is derived from wall-clock elapsed time (spec §3). A 1s tick
  /// only checks for expiry — remaining seconds are never written to disk.

  PlayerSessionProvider call(String testId) =>
      PlayerSessionProvider._(argument: testId, from: this);

  @override
  String toString() => r'playerSessionProvider';
}

/// Player for one [testId]. Creates or resumes an `attempts` row, downloads
/// questions, and autosaves answers to a local JSON file (spec §4).
///
/// The countdown is derived from wall-clock elapsed time (spec §3). A 1s tick
/// only checks for expiry — remaining seconds are never written to disk.

abstract class _$PlayerSession extends $AsyncNotifier<PlayerSessionState> {
  late final _$args = ref.$arg as String;
  String get testId => _$args;

  FutureOr<PlayerSessionState> build(String testId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<PlayerSessionState>, PlayerSessionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<PlayerSessionState>, PlayerSessionState>,
              AsyncValue<PlayerSessionState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
