// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'watermark_label_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Identity tiled over question content.
///
/// The WhatsApp number comes from Auth when the profile phone is still
/// empty. A synthetic internal email is never painted.

@ProviderFor(watermarkLabel)
final watermarkLabelProvider = WatermarkLabelProvider._();

/// Identity tiled over question content.
///
/// The WhatsApp number comes from Auth when the profile phone is still
/// empty. A synthetic internal email is never painted.

final class WatermarkLabelProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// Identity tiled over question content.
  ///
  /// The WhatsApp number comes from Auth when the profile phone is still
  /// empty. A synthetic internal email is never painted.
  WatermarkLabelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'watermarkLabelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$watermarkLabelHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return watermarkLabel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$watermarkLabelHash() => r'39d950a8158de08bb50574fdfa70ac36b0bb767f';
