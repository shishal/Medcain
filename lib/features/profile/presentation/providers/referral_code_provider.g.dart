// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'referral_code_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Shareable code for the signed-in student. Null when none has been issued.
///
/// `keepAlive` matches the profile provider so the code stays put while they
/// move between Profile and Plans. Call sites should invalidate this after
/// a refresh.

@ProviderFor(ownReferralCode)
final ownReferralCodeProvider = OwnReferralCodeProvider._();

/// Shareable code for the signed-in student. Null when none has been issued.
///
/// `keepAlive` matches the profile provider so the code stays put while they
/// move between Profile and Plans. Call sites should invalidate this after
/// a refresh.

final class OwnReferralCodeProvider
    extends
        $FunctionalProvider<
          AsyncValue<ReferralCode?>,
          ReferralCode?,
          FutureOr<ReferralCode?>
        >
    with $FutureModifier<ReferralCode?>, $FutureProvider<ReferralCode?> {
  /// Shareable code for the signed-in student. Null when none has been issued.
  ///
  /// `keepAlive` matches the profile provider so the code stays put while they
  /// move between Profile and Plans. Call sites should invalidate this after
  /// a refresh.
  OwnReferralCodeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownReferralCodeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownReferralCodeHash();

  @$internal
  @override
  $FutureProviderElement<ReferralCode?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ReferralCode?> create(Ref ref) {
    return ownReferralCode(ref);
  }
}

String _$ownReferralCodeHash() => r'd91a46ef40434c2f95f740a8f0d1be4238658451';
