// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attempt_review_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Per-question solutions for a submitted attempt.

@ProviderFor(attemptReview)
final attemptReviewProvider = AttemptReviewFamily._();

/// Per-question solutions for a submitted attempt.

final class AttemptReviewProvider
    extends
        $FunctionalProvider<
          AsyncValue<AttemptReview>,
          AttemptReview,
          FutureOr<AttemptReview>
        >
    with $FutureModifier<AttemptReview>, $FutureProvider<AttemptReview> {
  /// Per-question solutions for a submitted attempt.
  AttemptReviewProvider._({
    required AttemptReviewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'attemptReviewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$attemptReviewHash();

  @override
  String toString() {
    return r'attemptReviewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AttemptReview> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AttemptReview> create(Ref ref) {
    final argument = this.argument as String;
    return attemptReview(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AttemptReviewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$attemptReviewHash() => r'ea5c78e9599867bd3be9d2accc9dfeb2bf2ff177';

/// Per-question solutions for a submitted attempt.

final class AttemptReviewFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AttemptReview>, String> {
  AttemptReviewFamily._()
    : super(
        retry: null,
        name: r'attemptReviewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Per-question solutions for a submitted attempt.

  AttemptReviewProvider call(String attemptId) =>
      AttemptReviewProvider._(argument: attemptId, from: this);

  @override
  String toString() => r'attemptReviewProvider';
}
