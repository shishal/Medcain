// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attempt_results_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Submitted-attempt summary for the results screen.

@ProviderFor(attemptResults)
final attemptResultsProvider = AttemptResultsFamily._();

/// Submitted-attempt summary for the results screen.

final class AttemptResultsProvider
    extends
        $FunctionalProvider<
          AsyncValue<AttemptResults>,
          AttemptResults,
          FutureOr<AttemptResults>
        >
    with $FutureModifier<AttemptResults>, $FutureProvider<AttemptResults> {
  /// Submitted-attempt summary for the results screen.
  AttemptResultsProvider._({
    required AttemptResultsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'attemptResultsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$attemptResultsHash();

  @override
  String toString() {
    return r'attemptResultsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AttemptResults> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AttemptResults> create(Ref ref) {
    final argument = this.argument as String;
    return attemptResults(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AttemptResultsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$attemptResultsHash() => r'15d8aa02cfc4c64a9c5ab8dcf2273c70e0c099a4';

/// Submitted-attempt summary for the results screen.

final class AttemptResultsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AttemptResults>, String> {
  AttemptResultsFamily._()
    : super(
        retry: null,
        name: r'attemptResultsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Submitted-attempt summary for the results screen.

  AttemptResultsProvider call(String attemptId) =>
      AttemptResultsProvider._(argument: attemptId, from: this);

  @override
  String toString() => r'attemptResultsProvider';
}
