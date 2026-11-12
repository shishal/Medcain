import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/comic_card.dart';
import '../providers/notifications_provider.dart';

/// One-strip Home callout for the newest unread announcement.
class HomeUnreadAnnouncementBanner extends ConsumerWidget {
  const HomeUnreadAnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(latestUnreadAnnouncementProvider);
    if (item == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final comic = ComicColors.of(context);
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        0,
      ),
      child: ComicCard(
        color: Color.alphaBlend(
          scheme.secondary.withValues(
            alpha: brightness == Brightness.dark ? 0.22 : 0.12,
          ),
          comic.stickerLift,
        ),
        onTap: () => context.push(AppRoutes.notifications),
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.sm,
          Spacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.campaign_outlined, color: scheme.primary),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    item.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: () async {
                final result = await ref
                    .read(announcementsProvider.notifier)
                    .markRead(item.id);
                if (!context.mounted) return;
                if (result case Failure(:final message)) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
                }
              },
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
