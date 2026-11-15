// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checkout_launcher.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(checkoutLauncher)
final checkoutLauncherProvider = CheckoutLauncherProvider._();

final class CheckoutLauncherProvider
    extends
        $FunctionalProvider<
          CheckoutLauncher,
          CheckoutLauncher,
          CheckoutLauncher
        >
    with $Provider<CheckoutLauncher> {
  CheckoutLauncherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'checkoutLauncherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$checkoutLauncherHash();

  @$internal
  @override
  $ProviderElement<CheckoutLauncher> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CheckoutLauncher create(Ref ref) {
    return checkoutLauncher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CheckoutLauncher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CheckoutLauncher>(value),
    );
  }
}

String _$checkoutLauncherHash() => r'688fb560c6b915d311252a7936e580a4d9031781';
