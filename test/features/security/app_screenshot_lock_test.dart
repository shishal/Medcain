import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/security/data/screenshot_protection.dart';
import 'package:medico/features/security/domain/capture_event.dart';
import 'package:medico/features/security/presentation/widgets/app_screenshot_lock.dart';

class _FakeProtection implements ScreenshotProtection {
  final controller = StreamController<CaptureEvent>.broadcast();
  int acquireCount = 0;
  int releaseCount = 0;

  @override
  Stream<CaptureEvent> get events => controller.stream;

  @override
  Future<void> acquire() async {
    acquireCount++;
  }

  @override
  Future<void> release() async {
    releaseCount++;
  }
}

void main() {
  late _FakeProtection protection;

  setUp(() {
    protection = _FakeProtection();
  });

  tearDown(() async {
    await protection.controller.close();
  });

  testWidgets('acquires capture blocking for the life of the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          screenshotProtectionProvider.overrideWithValue(protection),
        ],
        child: const AppScreenshotLock(
          child: MaterialApp(home: Text('home')),
        ),
      ),
    );
    await tester.pump();

    expect(protection.acquireCount, 1);
    expect(protection.releaseCount, 0);
    expect(find.text('home'), findsOneWidget);
  });
}
