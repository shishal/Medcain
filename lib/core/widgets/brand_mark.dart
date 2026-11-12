import 'package:material_ui/material_ui.dart';

import '../theme/brand_assets.dart';

/// MEDCAIN ECG-M mark. Picks the light/dark asset so it stays visible on
/// the current canvas; optional [color] tints via [BlendMode.srcIn].
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 96,
    this.color,
    this.semanticLabel,
    this.asset,
  });

  final double size;
  final Color? color;

  /// Null when a nearby wordmark already names the app.
  final String? semanticLabel;

  /// Override [BrandAssets.markFor] when the canvas is not the theme surface
  /// (e.g. a forced dark splash while the app theme is light).
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final path =
        asset ?? BrandAssets.markFor(Theme.of(context).brightness);
    Widget image = Image.asset(
      path,
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
    if (color != null) {
      image = ColorFiltered(
        colorFilter: ColorFilter.mode(color!, BlendMode.srcIn),
        child: image,
      );
    }
    return image;
  }
}
