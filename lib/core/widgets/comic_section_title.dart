import 'package:material_ui/material_ui.dart';

import '../theme/spacing.dart';

/// Dashboard section heading: bold title, optional muted subtitle.
class ComicSectionTitle extends StatelessWidget {
  const ComicSectionTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              subtitle!,
              style: textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
