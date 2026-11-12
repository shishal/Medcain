// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'practice_plan_context_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Current plan's practice caps plus today's practice usage.
///
/// Invalidate after a successful session create so the remaining quota updates.

@ProviderFor(PracticePlanContextNotifier)
final practicePlanContextProvider = PracticePlanContextNotifierProvider._();

/// Current plan's practice caps plus today's practice usage.
///
/// Invalidate after a successful session create so the remaining quota updates.
final class PracticePlanContextNotifierProvider
    extends
        $AsyncNotifierProvider<
          PracticePlanContextNotifier,
          PracticePlanContext
        > {
  /// Current plan's practice caps plus today's practice usage.
  ///
  /// Invalidate after a successful session create so the remaining quota updates.
  PracticePlanContextNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'practicePlanContextProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$practicePlanContextNotifierHash();

  @$internal
  @override
  PracticePlanContextNotifier create() => PracticePlanContextNotifier();
}

String _$practicePlanContextNotifierHash() =>
    r'd0b4229da6680c15f25d6c34ae52d35f1dc01bec';

/// Current plan's practice caps plus today's practice usage.
///
/// Invalidate after a successful session create so the remaining quota updates.

abstract class _$PracticePlanContextNotifier
    extends $AsyncNotifier<PracticePlanContext> {
  FutureOr<PracticePlanContext> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<PracticePlanContext>, PracticePlanContext>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<PracticePlanContext>, PracticePlanContext>,
              AsyncValue<PracticePlanContext>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
