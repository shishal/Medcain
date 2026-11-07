import '../../../core/supabase/tables.dart';

/// Result of [RpcFunctions.claimActiveDevice].
class ClaimActiveDeviceResult {
  const ClaimActiveDeviceResult({
    required this.ok,
    required this.suspended,
    required this.justSuspended,
    required this.distinctDeviceCount,
    this.deviceLimit = false,
    this.maxDevices = 1,
  });

  final bool ok;
  final bool suspended;

  /// True when an older server suspended the plan on this claim.
  final bool justSuspended;
  final int distinctDeviceCount;

  /// True when this phone did not get a slot (Pro 1, Elite 2).
  final bool deviceLimit;
  final int maxDevices;

  factory ClaimActiveDeviceResult.fromJson(Map<String, dynamic> json) {
    return ClaimActiveDeviceResult(
      ok: json[ClaimActiveDeviceJson.ok] as bool? ?? false,
      suspended: json[ClaimActiveDeviceJson.suspended] as bool? ?? false,
      justSuspended:
          json[ClaimActiveDeviceJson.justSuspended] as bool? ?? false,
      distinctDeviceCount:
          (json[ClaimActiveDeviceJson.distinctDeviceCount] as num?)?.toInt() ??
          0,
      deviceLimit: json[ClaimActiveDeviceJson.deviceLimit] as bool? ?? false,
      maxDevices:
          (json[ClaimActiveDeviceJson.maxDevices] as num?)?.toInt() ?? 1,
    );
  }
}

/// User-facing copy for device / plan-sharing enforcement.
abstract final class DeviceSessionMessages {
  static const signedInElsewhere =
      'This account is signed in on another device.';

  static const planSuspended =
      'Your Pro access was paused because this account was used on too many '
      'devices. Contact support to restore it.';

  static const deviceLimit =
      'This phone is not registered on the account. Pro works on 1 device. '
      'Elite works on 2. Contact support to move a registration.';
}
