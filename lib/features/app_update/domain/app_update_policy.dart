import '../../../core/supabase/tables.dart';

/// The one row admins set: the lowest Android build that may open the app.
///
/// [minVersionCode] is the Play `versionCode` (the integer after `+` in
/// `pubspec.yaml`). `0` means the lock is off. [minVersionName] is only the
/// label on the update screen, such as `1.1.26`.
class AppUpdatePolicy {
  const AppUpdatePolicy({
    required this.minVersionCode,
    required this.minVersionName,
    this.updatedAt,
  });

  final int minVersionCode;
  final String minVersionName;
  final DateTime? updatedAt;

  /// No minimum. Every installed build may open the app.
  static const off = AppUpdatePolicy(minVersionCode: 0, minVersionName: '');

  bool get isEnforced => minVersionCode > 0;

  /// True when this install is older than the build the admin required.
  ///
  /// An install whose build number equals [minVersionCode] is allowed. That
  /// number is the minimum, so the build you just shipped can still open.
  bool blocksBuild(int installedVersionCode) {
    if (!isEnforced) return false;
    return installedVersionCode < minVersionCode;
  }

  factory AppUpdatePolicy.fromJson(Map<String, dynamic> json) {
    return AppUpdatePolicy(
      minVersionCode: _asInt(json[AppUpdatePolicyColumns.minVersionCode]),
      minVersionName:
          json[AppUpdatePolicyColumns.minVersionName] as String? ?? '',
      updatedAt: _date(json[AppUpdatePolicyColumns.updatedAt]),
    );
  }
}

/// What the startup gate should show after comparing the install to the rule.
class AppUpdateVerdict {
  const AppUpdateVerdict({
    required this.blocked,
    this.requiredVersionName = '',
  });

  final bool blocked;
  final String requiredVersionName;

  static const allowed = AppUpdateVerdict(blocked: false);

  /// [policy] is the server row when the fetch worked, otherwise the last
  /// row saved on the phone. Null means we have never learned a rule.
  factory AppUpdateVerdict.resolve({
    required int? installedVersionCode,
    required AppUpdatePolicy? policy,
  }) {
    if (policy == null) return allowed;
    if (installedVersionCode == null) {
      if (!policy.isEnforced) return allowed;
      return AppUpdateVerdict(
        blocked: true,
        requiredVersionName: policy.minVersionName,
      );
    }
    if (!policy.blocksBuild(installedVersionCode)) return allowed;
    return AppUpdateVerdict(
      blocked: true,
      requiredVersionName: policy.minVersionName,
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
