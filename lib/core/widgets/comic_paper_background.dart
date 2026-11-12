import 'package:material_ui/material_ui.dart';

import '../theme/comic_colors.dart';

/// Full-page canvas using the current theme paper (charcoal dark / gray light).
class ComicPaperBackground extends StatelessWidget {
  const ComicPaperBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: ComicColors.of(context).paper, child: child);
  }
}
