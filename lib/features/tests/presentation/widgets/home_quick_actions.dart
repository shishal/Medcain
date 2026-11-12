import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/comic_card.dart';

/// Secondary shortcuts once the shell owns Practice / Profile.
class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final comic = ComicColors.of(context);
    final actions = [
      (
        'Progress',
        Icons.local_fire_department_outlined,
        AppRoutes.progress,
        StickerFills.accentAt(0),
      ),
      (
        'Bookmarks',
        Icons.bookmark_outline,
        AppRoutes.bookmarks,
        StickerFills.accentAt(1),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: Spacing.sm),
            Expanded(
              child: ComicCard(
                color: comic.sticker,
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.md,
                ),
                onTap: () => context.push(actions[i].$3),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: actions[i].$4.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(actions[i].$2, color: actions[i].$4),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        actions[i].$1,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
