import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/comic_colors.dart';
import '../theme/spacing.dart';

/// Raised surface: hairline, ambient shadow, light squash on press.
/// Material so ListTile ink still paints.
class ComicCard extends StatefulWidget {
  const ComicCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.padding = const EdgeInsets.all(Spacing.md),
    this.borderRadius = AppTheme.cardRadius,
    this.semanticLabel,
    this.highlighted = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsets padding;
  final double borderRadius;
  final String? semanticLabel;
  final bool highlighted;

  @override
  State<ComicCard> createState() => _ComicCardState();
}

class _ComicCardState extends State<ComicCard> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final comic = ComicColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = widget.color ?? comic.sticker;
    final radius = BorderRadius.circular(widget.borderRadius);
    final borderColor = widget.highlighted
        ? scheme.primary.withValues(alpha: 0.85)
        : (dark
              ? Colors.white.withValues(alpha: 0.08)
              : scheme.outlineVariant.withValues(alpha: 0.55));

    // Dark Material elevation is easy to miss on charcoal. Custom shadows + a
    // top-left sheen give the Gecko-like “raised tile” look.
    final card = Material(
      color: fill,
      elevation: 0,
      surfaceTintColor: scheme.primary.withValues(alpha: dark ? 0.16 : 0.06),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: borderColor,
          width: widget.highlighted ? 1.5 : 1,
        ),
      ),
      child: Stack(
        children: [
          if (dark)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x1AFFFFFF), Color(0x00000000)],
                    stops: [0, 0.55],
                  ),
                ),
              ),
            ),
          Padding(padding: widget.padding, child: widget.child),
        ],
      ),
    );

    final lifted = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: comic.shadow,
            blurRadius: _pressed ? 6 : (dark ? 22 : 14),
            offset: Offset(0, _pressed ? 2 : (dark ? 10 : 6)),
            spreadRadius: _pressed ? 0 : -1,
          ),
          if (widget.highlighted)
            BoxShadow(
              color: scheme.primary.withValues(alpha: dark ? 0.32 : 0.22),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: card,
    );

    final scaled = AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: lifted,
    );

    if (widget.onTap == null) return scaled;

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap!();
        },
        child: scaled,
      ),
    );
  }
}
