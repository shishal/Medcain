import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/comic_colors.dart';

/// Shared reading-text size for one screen.
///
/// [ChangeNotifier] is a tiny observable: buttons and pinch gestures call
/// [setScale], and every [ReadingZoom] listening to this rebuilds. One
/// instance keeps the question stem and the answer the same size.
class ReadingTextZoom extends ChangeNotifier {
  double scale = 1;

  static const double minScale = 0.85;
  static const double maxScale = 2;
  static const double step = 0.15;

  bool get canDecrease => scale > minScale;
  bool get canIncrease => scale < maxScale;

  void setScale(double next) {
    final clamped = next.clamp(minScale, maxScale).toDouble();
    if (clamped == scale) return;
    scale = clamped;
    notifyListeners();
  }

  void decrease() => setScale(scale - step);
  void increase() => setScale(scale + step);
}

/// Applies [zoom] as a text scale (sharp glyphs, not a bitmap zoom).
///
/// Two-finger pinch changes [zoom]. A one-finger drag is ignored here so the
/// parent [ListView] can still scroll.
class ReadingZoom extends StatefulWidget {
  const ReadingZoom({super.key, required this.zoom, required this.child});

  final ReadingTextZoom zoom;
  final Widget child;

  @override
  State<ReadingZoom> createState() => _ReadingZoomState();
}

class _ReadingZoomState extends State<ReadingZoom> {
  // Captured at pinch start so each update is `start * gesture.scale`, not
  // compounded frame-by-frame (which would explode the font size).
  double _pinchStartScale = 1;

  @override
  void initState() {
    super.initState();
    widget.zoom.addListener(_onZoom);
  }

  @override
  void didUpdateWidget(ReadingZoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoom == widget.zoom) return;
    oldWidget.zoom.removeListener(_onZoom);
    widget.zoom.addListener(_onZoom);
  }

  @override
  void dispose() {
    widget.zoom.removeListener(_onZoom);
    super.dispose();
  }

  void _onZoom() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // scale(1) is the system text-size setting. Multiply it so pinch and
    // the A− / A+ buttons stack on top of accessibility scaling.
    final ambient = media.textScaler.scale(1);
    final zoomed = media.copyWith(
      textScaler: TextScaler.linear(ambient * widget.zoom.scale),
    );

    // RawGestureDetector (not GestureDetector) so we can swap in a recognizer
    // that gives up as soon as one finger moves. Otherwise a one-finger drag
    // on the question would be eaten and the page would not scroll.
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _TwoFingerScaleRecognizer:
            GestureRecognizerFactoryWithHandlers<_TwoFingerScaleRecognizer>(
              () => _TwoFingerScaleRecognizer(),
              (_TwoFingerScaleRecognizer instance) {
                instance.onStart = (_) {
                  _pinchStartScale = widget.zoom.scale;
                };
                instance.onUpdate = (details) {
                  if (details.pointerCount < 2) return;
                  widget.zoom.setScale(_pinchStartScale * details.scale);
                };
              },
            ),
      },
      child: MediaQuery(data: zoomed, child: widget.child),
    );
  }
}

/// Scale gesture that only wins the arena once a second finger is down.
class _TwoFingerScaleRecognizer extends ScaleGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    // The stock recognizer accepts a one-finger drag after a few pixels,
    // which beats the parent list's scroll. Leave the arena instead.
    if (event is PointerMoveEvent && pointerCount < 2) {
      resolve(GestureDisposition.rejected);
      return;
    }
    super.handleEvent(event);
  }
}

/// A− / A+ pill. Float this over the reader; it does not take a row in the
/// scroll content.
class ReadingZoomControls extends StatelessWidget {
  const ReadingZoomControls({super.key, required this.zoom});

  final ReadingTextZoom zoom;

  @override
  Widget build(BuildContext context) {
    final comic = ComicColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    // ListenableBuilder rebuilds only this pill when the scale changes,
    // so the rest of the screen does not have to setState.
    return ListenableBuilder(
      listenable: zoom,
      builder: (context, _) {
        return Material(
          color: comic.sticker,
          elevation: 6,
          shadowColor: comic.shadow,
          borderRadius: BorderRadius.circular(28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Smaller text',
                  onPressed: zoom.canDecrease ? zoom.decrease : null,
                  icon: const Icon(Icons.text_decrease, size: 20),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Larger text',
                  onPressed: zoom.canIncrease ? zoom.increase : null,
                  icon: const Icon(Icons.text_increase, size: 20),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
