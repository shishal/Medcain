import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'reading_text_zoom.dart';

/// Renders stored markdown (sample answers, explanations) using the
/// surrounding theme. Plain text still looks like a normal paragraph.
///
/// Selection/copy is off on purpose — DA, EX, tutor feedback, and review
/// answers are paid content. Links still open via [onTapLink].
///
/// Use this instead of [Text] inside a [ListView] — [MarkdownBody] does
/// not scroll on its own (`Markdown` would fight the parent scroll view).
class MarkdownCopy extends StatelessWidget {
  const MarkdownCopy({super.key, required this.data, this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium;
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base,
      strong: base?.copyWith(fontWeight: FontWeight.w700),
      em: base?.copyWith(fontStyle: FontStyle.italic),
      listBullet: base,
      blockquote: base?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      a: base?.copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
    );

    return MarkdownBody(
      data: data,
      selectable: false,
      styleSheet: sheet,
      onTapLink: (text, href, title) {
        if (href == null || href.isEmpty) return;
        final uri = Uri.tryParse(href);
        if (uri == null) return;
        launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}

/// Answer body that follows [zoom] (pinch, or the screen's A− / A+).
///
/// Pass the reader's [ReadingTextZoom] so the stem and the answer stay in
/// sync and the buttons can float over the page. With [zoom] omitted, this
/// owns a private scale and draws the buttons inline — handy for a widget
/// that is not inside a reader.
class ZoomableMarkdownCopy extends StatefulWidget {
  const ZoomableMarkdownCopy({super.key, required this.data, this.zoom});

  final String data;
  final ReadingTextZoom? zoom;

  @override
  State<ZoomableMarkdownCopy> createState() => _ZoomableMarkdownCopyState();
}

class _ZoomableMarkdownCopyState extends State<ZoomableMarkdownCopy> {
  ReadingTextZoom? _owned;

  ReadingTextZoom get _zoom => widget.zoom ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.zoom == null) _owned = ReadingTextZoom();
  }

  @override
  void didUpdateWidget(ZoomableMarkdownCopy oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.zoom != null) {
      _owned?.dispose();
      _owned = null;
    } else {
      _owned ??= ReadingTextZoom();
    }
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = ReadingZoom(
      zoom: _zoom,
      child: MarkdownCopy(data: widget.data),
    );
    // The reader floats one control for the whole page. Inline buttons only
    // appear when this widget owns the scale itself.
    if (widget.zoom != null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ReadingZoomControls(zoom: _zoom),
        ),
        body,
      ],
    );
  }
}
