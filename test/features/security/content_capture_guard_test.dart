import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/supabase/tables.dart';
import 'package:medico/features/security/data/screenshot_events_repository.dart';
import 'package:medico/features/security/data/screenshot_protection.dart';
import 'package:medico/features/security/domain/capture_event.dart';
import 'package:medico/features/security/presentation/providers/watermark_label_provider.dart';
import 'package:medico/features/security/presentation/widgets/content_capture_guard.dart';
import 'package:medico/features/security/presentation/widgets/content_watermark.dart';

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

class _FakeEventsRepository implements ScreenshotEventsRepository {
  final logs = <({String screen, String eventType})>[];

  @override
  Future<void> log({required String screen, required String eventType}) async {
    logs.add((screen: screen, eventType: eventType));
  }
}

void main() {
  late _FakeProtection protection;
  late _FakeEventsRepository events;

  setUp(() {
    protection = _FakeProtection();
    events = _FakeEventsRepository();
  });

  tearDown(() async {
    await protection.controller.close();
  });

  Future<void> pumpGuard(
    WidgetTester tester, {
    String watermark = 'Ada Lovelace · ada@example.com',
    bool showWatermark = true,
    Widget? child,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          screenshotProtectionProvider.overrideWithValue(protection),
          screenshotEventsRepositoryProvider.overrideWithValue(events),
          watermarkLabelProvider.overrideWithValue(watermark),
        ],
        child: MaterialApp(
          home: ContentCaptureGuard(
            screen: ContentScreens.testPlayer,
            watermark: showWatermark,
            child: child ?? const Scaffold(body: Text('question')),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('acquires protection on mount and releases on unmount', (
    tester,
  ) async {
    await pumpGuard(tester);
    expect(protection.acquireCount, 1);
    expect(find.text('question'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(protection.releaseCount, 1);
  });

  testWidgets('shows a snackbar and logs a screenshot event', (tester) async {
    await pumpGuard(tester);

    protection.controller.add(CaptureEvent.screenshot);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(ContentCaptureGuard.screenshotWarning), findsOneWidget);
    expect(events.logs, [
      (
        screen: ContentScreens.testPlayer,
        eventType: ScreenshotEventTypes.screenshot,
      ),
    ]);
  });

  testWidgets('shows a recording banner and logs once', (tester) async {
    await pumpGuard(tester);

    protection.controller.add(CaptureEvent.recordingStarted);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(events.logs, [
      (
        screen: ContentScreens.testPlayer,
        eventType: ScreenshotEventTypes.screenRecording,
      ),
    ]);
    expect(find.text(ContentCaptureGuard.recordingWarning), findsOneWidget);

    protection.controller.add(CaptureEvent.recordingStopped);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(ContentCaptureGuard.recordingWarning), findsNothing);
    expect(events.logs, hasLength(1));
  });

  testWidgets('tiles the identity watermark over question content', (
    tester,
  ) async {
    await pumpGuard(tester);
    final watermark = tester.widget<ContentWatermark>(
      find.byType(ContentWatermark),
    );
    expect(watermark.text, 'Ada Lovelace · ada@example.com');
  });

  testWidgets('hides the watermark when identity is empty', (tester) async {
    await pumpGuard(tester, watermark: '');
    expect(find.byType(ContentWatermark), findsNothing);
  });

  testWidgets('answer screens can opt out of the watermark', (tester) async {
    await pumpGuard(tester, showWatermark: false);
    expect(find.byType(ContentWatermark), findsNothing);
    expect(find.text('question'), findsOneWidget);
  });

  testWidgets('watermark does not block taps on the question', (tester) async {
    var tapped = false;
    await pumpGuard(
      tester,
      child: Scaffold(
        body: TextButton(
          onPressed: () => tapped = true,
          child: const Text('option A'),
        ),
      ),
    );

    await tester.tap(find.text('option A'));
    expect(tapped, isTrue);
  });
}
