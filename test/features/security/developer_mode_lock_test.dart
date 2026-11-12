import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medico/features/security/data/developer_mode_monitor.dart';
import 'package:medico/features/security/presentation/screens/developer_mode_blocked_screen.dart';
import 'package:medico/features/security/presentation/widgets/developer_mode_lock.dart';

class _FakeMonitor implements DeveloperModeMonitor {
  _FakeMonitor(this.enabled);

  bool enabled;
  final changes = StreamController<bool>.broadcast();
  int openSettingsCount = 0;
  int releaseShieldCount = 0;

  void emit(bool value) {
    enabled = value;
    changes.add(value);
  }

  @override
  bool get enforces => true;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Stream<bool> watch() => changes.stream;

  @override
  Future<void> openSettings() async {
    openSettingsCount++;
  }

  @override
  Future<void> releaseShield() async {
    releaseShieldCount++;
  }
}

class _HangingMonitor implements DeveloperModeMonitor {
  final pending = Completer<bool>();

  @override
  bool get enforces => true;

  @override
  Future<bool> isEnabled() => pending.future;

  @override
  Stream<bool> watch() => const Stream.empty();

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> releaseShield() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpLock(
    WidgetTester tester, {
    required DeveloperModeMonitor monitor,
    required Widget child,
  }) async {
    if (monitor is _FakeMonitor) {
      addTearDown(monitor.changes.close);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [developerModeMonitorProvider.overrideWithValue(monitor)],
        child: DeveloperModeLock(child: MaterialApp(home: child)),
      ),
    );
  }

  testWidgets('hides content until the check finishes', (tester) async {
    final monitor = _HangingMonitor();
    await pumpLock(
      tester,
      monitor: monitor,
      child: const Text('Question stem'),
    );
    await tester.pump();

    expect(find.text('Question stem'), findsNothing);
    expect(find.text(DeveloperModeBlockedScreen.title), findsNothing);

    monitor.pending.complete(false);
    // complete() schedules a microtask; the frame after that paints the app.
    await tester.pump();
    await tester.pump();

    expect(find.text('Question stem'), findsOneWidget);
  });

  testWidgets('shows the lock screen and drops the question', (tester) async {
    final monitor = _FakeMonitor(true);
    await pumpLock(
      tester,
      monitor: monitor,
      child: const Text('Question stem'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Question stem'), findsNothing);
    expect(find.text(DeveloperModeBlockedScreen.title), findsOneWidget);
    expect(find.text(DeveloperModeBlockedScreen.body), findsOneWidget);
    expect(monitor.releaseShieldCount, 1);
  });

  testWidgets('locks immediately when developer mode turns on', (tester) async {
    final monitor = _FakeMonitor(false);
    await pumpLock(
      tester,
      monitor: monitor,
      child: const Text('Question stem'),
    );
    await tester.pump();
    expect(find.text('Question stem'), findsOneWidget);

    monitor.emit(true);
    await tester.pump();
    await tester.pump();

    expect(find.text('Question stem'), findsNothing);
    expect(find.text(DeveloperModeBlockedScreen.title), findsOneWidget);
    expect(monitor.releaseShieldCount, 1);
  });

  testWidgets('unlocks when developer mode turns off', (tester) async {
    final monitor = _FakeMonitor(true);
    await pumpLock(
      tester,
      monitor: monitor,
      child: const Text('Question stem'),
    );
    await tester.pump();
    expect(find.text(DeveloperModeBlockedScreen.title), findsOneWidget);

    monitor.emit(false);
    await tester.pump();

    expect(find.text(DeveloperModeBlockedScreen.title), findsNothing);
    expect(find.text('Question stem'), findsOneWidget);
  });

  testWidgets('rechecks when the app returns to the foreground', (
    tester,
  ) async {
    final monitor = _FakeMonitor(false);
    await pumpLock(
      tester,
      monitor: monitor,
      child: const Text('Question stem'),
    );
    await tester.pump();
    expect(find.text('Question stem'), findsOneWidget);

    monitor.enabled = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(find.text('Question stem'), findsNothing);
    expect(find.text(DeveloperModeBlockedScreen.title), findsOneWidget);
  });

  testWidgets('Open Developer options calls the monitor', (tester) async {
    final monitor = _FakeMonitor(true);
    await pumpLock(tester, monitor: monitor, child: const SizedBox.shrink());
    await tester.pump();

    await tester.tap(find.text(DeveloperModeBlockedScreen.openSettingsLabel));
    await tester.pump();

    expect(monitor.openSettingsCount, 1);
  });
}
