// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'developer_mode_monitor.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(developerModeMonitor)
final developerModeMonitorProvider = DeveloperModeMonitorProvider._();

final class DeveloperModeMonitorProvider
    extends
        $FunctionalProvider<
          DeveloperModeMonitor,
          DeveloperModeMonitor,
          DeveloperModeMonitor
        >
    with $Provider<DeveloperModeMonitor> {
  DeveloperModeMonitorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'developerModeMonitorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$developerModeMonitorHash();

  @$internal
  @override
  $ProviderElement<DeveloperModeMonitor> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DeveloperModeMonitor create(Ref ref) {
    return developerModeMonitor(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeveloperModeMonitor value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeveloperModeMonitor>(value),
    );
  }
}

String _$developerModeMonitorHash() =>
    r'688333a54d08be7d272b01d2f274601710c58cd8';
