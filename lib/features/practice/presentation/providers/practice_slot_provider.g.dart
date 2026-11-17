// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'practice_slot_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The signed-in student's one practice row, or null.
///
/// Invalidate after a session is created so Resume disappears once the
/// previous row has been replaced.

@ProviderFor(PracticeSlotNotifier)
final practiceSlotProvider = PracticeSlotNotifierProvider._();

/// The signed-in student's one practice row, or null.
///
/// Invalidate after a session is created so Resume disappears once the
/// previous row has been replaced.
final class PracticeSlotNotifierProvider
    extends $AsyncNotifierProvider<PracticeSlotNotifier, PracticeSlot?> {
  /// The signed-in student's one practice row, or null.
  ///
  /// Invalidate after a session is created so Resume disappears once the
  /// previous row has been replaced.
  PracticeSlotNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'practiceSlotProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$practiceSlotNotifierHash();

  @$internal
  @override
  PracticeSlotNotifier create() => PracticeSlotNotifier();
}

String _$practiceSlotNotifierHash() =>
    r'fa48cd664b0ebdab4a7dabf895330eda31ad899d';

/// The signed-in student's one practice row, or null.
///
/// Invalidate after a session is created so Resume disappears once the
/// previous row has been replaced.

abstract class _$PracticeSlotNotifier extends $AsyncNotifier<PracticeSlot?> {
  FutureOr<PracticeSlot?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<PracticeSlot?>, PracticeSlot?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<PracticeSlot?>, PracticeSlot?>,
              AsyncValue<PracticeSlot?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
