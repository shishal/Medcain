import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/tables.dart';
import '../../../../core/theme/spacing.dart';
import '../../data/screenshot_events_repository.dart';
import '../../data/screenshot_protection.dart';
import '../../domain/capture_event.dart';
import '../providers/watermark_label_provider.dart';
import 'content_watermark.dart';

/// Blocks screenshots/recording while mounted, warns on iOS detection,
/// logs the event, and tiles a faint identity watermark (Phase 8.2).
///
/// Wrap screens that show question content. Android FLAG_SECURE stays on
/// for the whole app (see `AppScreenshotLock`); this widget still watermarks
/// and logs iOS capture attempts.
class ContentCaptureGuard extends ConsumerStatefulWidget {
  const ContentCaptureGuard({
    super.key,
    required this.screen,
    required this.child,
    this.watermark = true,
  });

  /// Stored on `screenshot_events.screen` (see [ContentScreens]).
  final String screen;
  final Widget child;

  /// Set false on answer screens: capture blocking and logging stay on, but
  /// the identity overlay is not drawn over the answer text.
  final bool watermark;

  static const screenshotWarning =
      "Screenshots of questions aren't allowed. This has been logged.";

  static const recordingWarning =
      "Screen recording detected. Capturing test content isn't allowed.";

  @override
  ConsumerState<ContentCaptureGuard> createState() =>
      _ContentCaptureGuardState();
}

class _ContentCaptureGuardState extends ConsumerState<ContentCaptureGuard> {
  late final ScreenshotProtection _protection;
  StreamSubscription<CaptureEvent>? _subscription;
  bool _disposed = false;
  bool _acquired = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _protection = ref.read(screenshotProtectionProvider);
    // Fire-and-forget: don't await native FLAG_SECURE; first frame can
    // still render. `unawaited` marks that the missing await is intentional.
    unawaited(_arm());
  }

  Future<void> _arm() async {
    // Subscribe before [acquire] so an event during native setup is not missed.
    _subscription = _protection.events.listen(_onEvent);
    await _protection.acquire();
    if (_disposed) {
      await _subscription?.cancel();
      await _protection.release();
      return;
    }
    _acquired = true;
  }

  void _onEvent(CaptureEvent event) {
    if (!mounted) return;
    switch (event) {
      case CaptureEvent.screenshot:
        _warnScreenshot();
        unawaited(
          ref
              .read(screenshotEventsRepositoryProvider)
              .log(
                screen: widget.screen,
                eventType: ScreenshotEventTypes.screenshot,
              ),
        );
        return;
      case CaptureEvent.recordingStarted:
        setState(() => _isRecording = true);
        unawaited(
          ref
              .read(screenshotEventsRepositoryProvider)
              .log(
                screen: widget.screen,
                eventType: ScreenshotEventTypes.screenRecording,
              ),
        );
        return;
      case CaptureEvent.recordingStopped:
        setState(() => _isRecording = false);
    }
  }

  void _warnScreenshot() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(ContentCaptureGuard.screenshotWarning)),
      );
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    if (_acquired) {
      unawaited(_protection.release());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the singleton alive while this screen is showing.
    ref.watch(screenshotProtectionProvider);
    final watermarkText = ref.watch(watermarkLabelProvider);

    return Column(
      children: [
        if (_isRecording) const _RecordingBanner(),
        Expanded(
          child: Stack(
            children: [
              widget.child,
              if (widget.watermark && watermarkText.isNotEmpty)
                Positioned.fill(child: ContentWatermark(text: watermarkText)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordingBanner extends StatelessWidget {
  const _RecordingBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Text(
            ContentCaptureGuard.recordingWarning,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.onErrorContainer),
          ),
        ),
      ),
    );
  }
}
