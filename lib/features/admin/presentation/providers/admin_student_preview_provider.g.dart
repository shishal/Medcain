// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_student_preview_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// In-memory switch so an admin can open the student screens on this phone.
///
/// A [Notifier] holds a value the rest of the app can read. This one is not
/// written to disk: killing the app starts again at `false`, so the next
/// launch opens Admin. Sign-out clears it too. Students never reach the
/// Admin control that turns it on.

@ProviderFor(AdminStudentPreview)
final adminStudentPreviewProvider = AdminStudentPreviewProvider._();

/// In-memory switch so an admin can open the student screens on this phone.
///
/// A [Notifier] holds a value the rest of the app can read. This one is not
/// written to disk: killing the app starts again at `false`, so the next
/// launch opens Admin. Sign-out clears it too. Students never reach the
/// Admin control that turns it on.
final class AdminStudentPreviewProvider
    extends $NotifierProvider<AdminStudentPreview, bool> {
  /// In-memory switch so an admin can open the student screens on this phone.
  ///
  /// A [Notifier] holds a value the rest of the app can read. This one is not
  /// written to disk: killing the app starts again at `false`, so the next
  /// launch opens Admin. Sign-out clears it too. Students never reach the
  /// Admin control that turns it on.
  AdminStudentPreviewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'adminStudentPreviewProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$adminStudentPreviewHash();

  @$internal
  @override
  AdminStudentPreview create() => AdminStudentPreview();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$adminStudentPreviewHash() =>
    r'841c9b47d7926f1f1b84bfd078871e6616f48694';

/// In-memory switch so an admin can open the student screens on this phone.
///
/// A [Notifier] holds a value the rest of the app can read. This one is not
/// written to disk: killing the app starts again at `false`, so the next
/// launch opens Admin. Sign-out clears it too. Students never reach the
/// Admin control that turns it on.

abstract class _$AdminStudentPreview extends $Notifier<bool> {
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
