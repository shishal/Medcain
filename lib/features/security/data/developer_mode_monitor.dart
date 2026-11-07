import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'developer_mode_monitor.g.dart';

/// Whether Android Developer options or USB debugging is on.
///
/// USB debugging can capture the screen even when screenshots are blocked.
/// iOS has no equivalent switch this app can read, so [enforces] is false
/// there and the app opens normally.
abstract class DeveloperModeMonitor {
  /// False in debug builds and on iOS. The lock shows the app immediately
  /// instead of waiting on a native call.
  bool get enforces;

  /// True when content must stay hidden.
  ///
  /// On Android, a failed check stays locked: a broken channel must not
  /// leave question text on screen.
  Future<bool> isEnabled();

  /// Pushes a new value when the setting changes. Empty when [enforces]
  /// is false.
  Stream<bool> watch();

  /// Opens the system Developer options page.
  Future<void> openSettings();

  /// Native cover can come down; Dart has painted the lock screen.
  Future<void> releaseShield();
}

/// Talks to [DeveloperModeGate] in the Android app.
///
/// A [MethodChannel] is a named pipe between Dart and Kotlin. Dart calls
/// a method by name; Kotlin runs it and sends a value back. An
/// [EventChannel] is the same pipe, but Android pushes an update when
/// Developer options are toggled instead of Dart asking once.
class PlatformDeveloperModeMonitor implements DeveloperModeMonitor {
  /// [enforce] is off when [kDebugMode] is true. `flutter run` needs
  /// Developer options, so a debug build would otherwise lock itself.
  /// Profile and release builds enforce the check.
  PlatformDeveloperModeMonitor({
    bool? enforce,
    MethodChannel? channel,
    EventChannel? events,
  }) : _enforce = enforce ?? !kDebugMode,
       _channel = channel ?? const MethodChannel(_methodName),
       _events = events ?? const EventChannel(_eventName);

  static const _methodName = 'com.shishal.medico/developer_mode';
  static const _eventName = 'com.shishal.medico/developer_mode/events';

  final bool _enforce;
  final MethodChannel _channel;
  final EventChannel _events;

  bool get _active =>
      _enforce && defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get enforces => _active;

  @override
  Future<bool> isEnabled() async {
    if (!_active) return false;
    try {
      final enabled = await _channel.invokeMethod<bool>('isEnabled');
      // No answer is treated as locked. See the class docs.
      return enabled ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Stream<bool> watch() {
    if (!_active) return const Stream.empty();
    return _events.receiveBroadcastStream().map((event) => event == true);
  }

  @override
  Future<void> openSettings() async {
    if (!_active) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on MissingPluginException {
      // Lock screen stays up; the student can open Settings themselves.
    } on PlatformException {
      // This device has no Developer options activity.
    }
  }

  @override
  Future<void> releaseShield() async {
    if (!_active) return;
    try {
      await _channel.invokeMethod<void>('releaseShield');
    } on MissingPluginException {
      // Nothing native to remove.
    } on PlatformException {
      // Shield stays up; the lock screen is already underneath it.
    }
  }
}

@Riverpod(keepAlive: true)
DeveloperModeMonitor developerModeMonitor(Ref ref) {
  return PlatformDeveloperModeMonitor();
}
