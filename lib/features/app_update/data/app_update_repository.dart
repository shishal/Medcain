import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../domain/app_update_policy.dart';

part 'app_update_repository.g.dart';

/// Last rule this install learned. Used when the phone is offline so a
/// required update still blocks after the first successful check.
const requiredVersionCodePrefKey = 'medico_required_version_code';
const requiredVersionNamePrefKey = 'medico_required_version_name';

/// How long startup will wait for the rule before falling back to the
/// saved copy (or allowing the app, if we have never saved one).
const appUpdateFetchTimeout = Duration(seconds: 6);

/// Version baked into the installed package, plus the remote minimum.
class InstalledBuild {
  const InstalledBuild({required this.versionName, required this.versionCode});

  /// `1.1.25` from `pubspec.yaml` `version:`.
  final String versionName;

  /// The integer after `+` in `pubspec.yaml`. Play calls this versionCode.
  final int versionCode;

  String get label => '$versionName ($versionCode)';
}

class AppUpdateRepository {
  AppUpdateRepository(this._client);

  final SupabaseClient _client;

  /// Reads `version` and `buildNumber` from the installed app, not from a
  /// constant. `buildNumber` is the Android versionCode.
  Future<InstalledBuild> installedBuild() async {
    final info = await PackageInfo.fromPlatform();
    return InstalledBuild(
      versionName: info.version,
      versionCode: int.tryParse(info.buildNumber) ?? 0,
    );
  }

  /// Asks Supabase, then remembers the answer. Throws on network failure
  /// so [evaluate] can use the remembered row instead.
  Future<AppUpdatePolicy> fetchPolicy() async {
    final raw = await _client.rpc(RpcFunctions.appUpdatePolicy);
    if (raw is! Map) {
      throw const FormatException('Update rule was not a JSON object.');
    }
    final policy = AppUpdatePolicy.fromJson(Map<String, dynamic>.from(raw));
    await _cache(policy);
    return policy;
  }

  Future<AppUpdatePolicy?> readCachedPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(requiredVersionCodePrefKey)) return null;
    return AppUpdatePolicy(
      minVersionCode: prefs.getInt(requiredVersionCodePrefKey) ?? 0,
      minVersionName: prefs.getString(requiredVersionNamePrefKey) ?? '',
    );
  }

  /// Server row wins. If that call fails, the last saved row still applies.
  /// A phone that has never reached the server is allowed through so a
  /// network blip does not lock a current install.
  Future<AppUpdateVerdict> evaluate() async {
    int? installedCode;
    try {
      installedCode = (await installedBuild()).versionCode;
    } catch (_) {
      installedCode = null;
    }

    AppUpdatePolicy? policy;
    try {
      policy = await fetchPolicy().timeout(appUpdateFetchTimeout);
    } catch (_) {
      try {
        policy = await readCachedPolicy();
      } catch (_) {
        policy = null;
      }
    }

    return AppUpdateVerdict.resolve(
      installedVersionCode: installedCode,
      policy: policy,
    );
  }

  Future<void> _cache(AppUpdatePolicy policy) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(requiredVersionCodePrefKey, policy.minVersionCode);
      await prefs.setString(requiredVersionNamePrefKey, policy.minVersionName);
    } catch (_) {
      // Remembering the rule is a backup. A prefs failure must not hide a
      // rule we already fetched.
    }
  }
}

@Riverpod(keepAlive: true)
AppUpdateRepository appUpdateRepository(Ref ref) {
  return AppUpdateRepository(ref.watch(supabaseClientProvider));
}
