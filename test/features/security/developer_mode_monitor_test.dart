import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medico/features/security/data/developer_mode_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.shishal.medico/developer_mode');
  var calls = 0;

  void setHandler(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          return handler(call);
        });
  }

  setUp(() {
    calls = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('debug builds do not ask Android', () async {
    setHandler((_) async => true);
    final monitor = PlatformDeveloperModeMonitor(enforce: false);

    expect(monitor.enforces, isFalse);
    expect(await monitor.isEnabled(), isFalse);
    expect(calls, 0);
    expect(await monitor.watch().isEmpty, isTrue);
  });

  test('iOS does not ask Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    setHandler((_) async => true);
    final monitor = PlatformDeveloperModeMonitor(enforce: true);

    expect(monitor.enforces, isFalse);
    expect(await monitor.isEnabled(), isFalse);
    expect(calls, 0);
  });

  test('reports developer mode when Android says it is on', () async {
    setHandler((call) async {
      expect(call.method, 'isEnabled');
      return true;
    });
    final monitor = PlatformDeveloperModeMonitor(enforce: true);

    expect(monitor.enforces, isTrue);
    expect(await monitor.isEnabled(), isTrue);
  });

  test('stays open when Android says developer mode is off', () async {
    setHandler((_) async => false);
    final monitor = PlatformDeveloperModeMonitor(enforce: true);

    expect(await monitor.isEnabled(), isFalse);
  });

  test('locks when Android returns no answer or throws', () async {
    final monitor = PlatformDeveloperModeMonitor(enforce: true);

    setHandler((_) async => null);
    expect(await monitor.isEnabled(), isTrue);

    setHandler((_) async {
      throw PlatformException(code: 'fail');
    });
    expect(await monitor.isEnabled(), isTrue);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(await monitor.isEnabled(), isTrue);
  });

  test('openSettings and releaseShield call the matching methods', () async {
    final methods = <String>[];
    setHandler((call) async {
      methods.add(call.method);
      return null;
    });
    final monitor = PlatformDeveloperModeMonitor(enforce: true);

    await monitor.openSettings();
    await monitor.releaseShield();

    expect(methods, ['openSettings', 'releaseShield']);
  });
}
