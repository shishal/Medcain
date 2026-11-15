import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Preference key for the stable install id used by single-device login.
const deviceIdPrefKey = 'medico_device_id';

String? _cachedDeviceId;

/// Returns a UUID that stays stable for this app install (SharedPreferences).
///
/// Not a hardware IMEI — reinstall generates a new id (counts as a new device
/// toward the lifetime cap).
Future<String> getOrCreateDeviceId() async {
  final cached = _cachedDeviceId;
  if (cached != null && cached.isNotEmpty) return cached;
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(deviceIdPrefKey);
  if (existing != null && existing.isNotEmpty) {
    _cachedDeviceId = existing;
    return existing;
  }
  final created = _randomUuidV4();
  await prefs.setString(deviceIdPrefKey, created);
  _cachedDeviceId = created;
  return created;
}

/// RFC 4122 version-4 UUID from secure random bytes (no extra package).
String _randomUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  // Version 4 + variant bits.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
