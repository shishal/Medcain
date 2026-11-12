import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'reading_text_zoom.dart';

/// flutter_markdown_plus still takes the old framework [ThemeData], so the
/// sheet is built from the current theme's text styles instead.
MarkdownStyleSheet _styleSheet(ThemeData theme, TextStyle? base) {
  final body = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
  final cardColor = theme.cardTheme.color ?? theme.cardColor;
  return MarkdownStyleSheet(
    a: base?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    ),
    p: base,
    pPadding: EdgeInsets.zero,
    code: body.copyWith(
      backgroundColor: theme.cardTheme.color,
      fontFamily: 'monospace',
      fontSize: (body.fontSize ?? 14) * 0.85,
    ),
    h1: theme.textTheme.headlineSmall,
    h1Padding: EdgeInsets.zero,
    h2: theme.textTheme.titleLarge,
    h2Padding: EdgeInsets.zero,
    h3: theme.textTheme.titleMedium,
    h3Padding: EdgeInsets.zero,
    h4: theme.textTheme.bodyLarge,
    h4Padding: EdgeInsets.zero,
    h5: theme.textTheme.bodyLarge,
    h5Padding: EdgeInsets.zero,
    h6: theme.textTheme.bodyLarge,
    h6Padding: EdgeInsets.zero,
    em: base?.copyWith(fontStyle: FontStyle.italic),
    strong: base?.copyWith(fontWeight: FontWeight.w700),
    del: const TextStyle(decoration: TextDecoration.lineThrough),
    blockquote: base?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    img: body,
    checkbox: body.copyWith(color: theme.primaryColor),
    blockSpacing: 8,
    listIndent: 24,
    listBullet: base,
    listBulletPadding: const EdgeInsets.only(right: 4),
    tableHead: const TextStyle(fontWeight: FontWeight.w600),
    tableBody: body,
    tableHeadAlign: TextAlign.center,
    tablePadding: const EdgeInsets.only(bottom: 4),
    tableBorder: TableBorder.all(color: theme.dividerColor),
    tableColumnWidth: const FlexColumnWidth(),
    tableCellsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    tableCellsDecoration: const BoxDecoration(),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    blockquoteDecoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(3),
      border: Border(
        left: BorderSide(color: theme.colorScheme.primary, width: 3),
      ),
    ),
    codeblockPadding: const EdgeInsets.all(8),
    codeblockDecoration: BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(2),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(width: 5, color: theme.dividerColor)),
    ),
  );
}

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
    final sheet = _styleSheet(theme, base);

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
