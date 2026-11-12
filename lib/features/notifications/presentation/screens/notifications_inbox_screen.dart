import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../domain/app_announcement.dart';
import '../providers/notifications_provider.dart';

/// Full list of broadcast announcements for the signed-in user.
class NotificationsInboxScreen extends ConsumerWidget {
  const NotificationsInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(AppRoutes.home);
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(announcementsProvider);
          await ref.read(announcementsProvider.future);
        },
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => const AsyncLoadingView(),
          error: (error, _) => AsyncErrorView(
            message: UserFacingError.display(error),
            onAction: () => ref.invalidate(announcementsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: const AsyncEmptyView(
                      icon: Icons.notifications_none_rounded,
                      message:
                          'No notifications yet. Check back when we post an '
                          'update or offer.',
                    ),
                  ),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(Spacing.md),
              itemCount: items.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: _AnnouncementTile(item: items[index]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AnnouncementTile extends ConsumerWidget {
  const _AnnouncementTile({required this.item});

  final AppAnnouncement item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final comic = ComicColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return ComicCard(
      highlighted: !item.isRead,
      color: item.isRead
          ? null
          : Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.08),
              comic.stickerLift,
            ),
      onTap: () => _open(context, ref),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _iconFor(item.category),
            color: item.isRead ? scheme.onSurfaceVariant : scheme.primary,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.categoryLabel,
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!item.isRead) ...[
                      const SizedBox(width: Spacing.sm),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      _shortDate(item.publishedAt),
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  item.title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: item.isRead ? FontWeight.w600 : FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(announcementsProvider.notifier)
        .markRead(item.id);
    if (!context.mounted) return;

    if (result case Failure(:final message)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final link = item.deepLink?.trim();
    if (link != null && link.startsWith('/')) {
      context.push(link);
    }
  }

  static IconData _iconFor(String category) {
    return switch (category) {
      'version' => Icons.system_update_rounded,
      'offer' => Icons.local_offer_outlined,
      'payment' => Icons.payments_outlined,
      _ => Icons.campaign_outlined,
    };
  }

  static String _shortDate(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameYear = local.year == now.year;
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = '${months[local.month - 1]} ${local.day}';
    return sameYear ? day : '$day ${local.year}';
  }
}
