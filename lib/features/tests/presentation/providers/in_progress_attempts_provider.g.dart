// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'in_progress_attempts_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// In-progress attempts for the signed-in user, reconciled against the server.
///
/// Local files win for answers (offline). If the server says the attempt was
/// already submitted, the local file is deleted so we don't offer a dead resume.

@ProviderFor(InProgressAttempts)
final inProgressAttemptsProvider = InProgressAttemptsProvider._();

/// In-progress attempts for the signed-in user, reconciled against the server.
///
/// Local files win for answers (offline). If the server says the attempt was
/// already submitted, the local file is deleted so we don't offer a dead resume.
final class InProgressAttemptsProvider
    extends $AsyncNotifierProvider<InProgressAttempts, List<ResumableAttempt>> {
  /// In-progress attempts for the signed-in user, reconciled against the server.
  ///
  /// Local files win for answers (offline). If the server says the attempt was
  /// already submitted, the local file is deleted so we don't offer a dead resume.
  InProgressAttemptsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inProgressAttemptsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inProgressAttemptsHash();

  @$internal
  @override
  InProgressAttempts create() => InProgressAttempts();
}

String _$inProgressAttemptsHash() =>
    r'352e6502bd2f3fe1ab11f0650639cd0eabd77303';

/// In-progress attempts for the signed-in user, reconciled against the server.
///
/// Local files win for answers (offline). If the server says the attempt was
/// already submitted, the local file is deleted so we don't offer a dead resume.

abstract class _$InProgressAttempts
    extends $AsyncNotifier<List<ResumableAttempt>> {
  FutureOr<List<ResumableAttempt>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<ResumableAttempt>>, List<ResumableAttempt>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<ResumableAttempt>>,
                List<ResumableAttempt>
              >,
              AsyncValue<List<ResumableAttempt>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
