import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/brand_assets.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/brand_wordmark.dart';
import '../../../../core/widgets/comic_mascot.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../notifications/presentation/providers/notifications_provider.dart';
import '../../../profile/domain/plan_tier.dart';
import '../../../profile/presentation/providers/current_plan_provider.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../../../progress/presentation/providers/ug_home_providers.dart';

/// Greeting: brand + Docci + name + year/university.
/// A free plan shows an Upgrade control beside the pill that opens Plans.
class HomeHeroBanner extends ConsumerWidget {
  const HomeHeroBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    final plan = ref.watch(currentPlanProvider).value;
    final streak = ref.watch(studyProgressProvider).value?.streak ?? 0;
    final unis = ref.watch(universitiesProvider).value ?? const [];
    final phases = ref.watch(mbbsPhasesProvider).value ?? const [];
    final name = profile?.fullName?.trim();
    final hello = (name == null || name.isEmpty)
        ? 'Hi intern'
        : 'Hi, ${_firstName(name)}';

    University? uni;
    for (final u in unis) {
      if (u.id == profile?.universityId) uni = u;
    }
    String? yearName;
    for (final p in phases) {
      if (p.id == profile?.mbbsPhaseId) yearName = p.name;
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final subtitleParts = [
      ?yearName,
      ?uni?.code,
      if (streak > 0) '$streak-day streak',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: BrandWordmark(markSize: 28, compact: true),
              ),
              const _NotificationsBellButton(),
              IconButton.filledTonal(
                tooltip: 'Search',
                onPressed: () => context.push(AppRoutes.search),
                icon: const Icon(Icons.search_rounded),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              const ComicMascot(
                asset: BrandAssets.mascotWave,
                size: 56,
                heroTag: BrandAssets.mascotHeroTag,
                bounce: false,
                circleBackdrop: true,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hello,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (plan != null) ...[
                          _PlanPill(plan: plan),
                          if (plan == PlanTier.free) const _UpgradePlanLink(),
                          const SizedBox(width: Spacing.sm),
                        ],
                        Expanded(
                          child: Text(
                            subtitleParts.isEmpty
                                ? 'Pick a subject to start.'
                                : subtitleParts.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _firstName(String full) {
    final space = full.indexOf(' ');
    return space <= 0 ? full : full.substring(0, space);
  }
}

class _NotificationsBellButton extends ConsumerWidget {
  const _NotificationsBellButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadAnnouncementCountProvider);
    final icon = IconButton.filledTonal(
      tooltip: 'Notifications',
      onPressed: () => context.push(AppRoutes.notifications),
      icon: const Icon(Icons.notifications_outlined),
    );
    if (unread <= 0) return icon;

    return Badge(
      label: Text(unread > 9 ? '9+' : '$unread'),
      child: icon,
    );
  }
}

/// Plan badge. Gold is reserved for paid tiers (see
/// docs/01_PROJECT_FOUNDATION.md) — a free account used to wear a gold chip.
class _PlanPill extends StatelessWidget {
  const _PlanPill({required this.plan});

  final PlanTier plan;

  @override
  Widget build(BuildContext context) {
    final comic = ComicColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final paid = plan != PlanTier.free;
    final fg = paid ? comic.proGold : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: paid
            ? comic.proGold.withValues(alpha: 0.2)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        plan.label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Sits beside the Free pill and opens the plan comparison screen.
class _UpgradePlanLink extends StatelessWidget {
  const _UpgradePlanLink();

  @override
  Widget build(BuildContext context) {
    final comic = ComicColors.of(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: comic.proGold,
      fontWeight: FontWeight.w700,
    );

    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: comic.proGold,
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
        textStyle: style,
      ),
      onPressed: () => context.push(AppRoutes.upgrade),
      child: const Text('Upgrade'),
    );
  }
}

/// Quiet catalog size under the greeting.
class HomeCoverageBanner extends ConsumerWidget {
  const HomeCoverageBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(universityCoverageProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (c) {
        final scheme = Theme.of(context).colorScheme;
        // v1 content is KUHS, so the other universities really do have zero.
        // "0 PYQs · 0 papers" reads as broken; say what is actually going on.
        final line = c.paperCount == 0
            ? 'No papers tagged for your university yet — KUHS is live first.'
            : '${c.pyqCount} PYQs · ${c.paperCount} papers';
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.sm,
            Spacing.lg,
            0,
          ),
          child: Text(
            line,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        );
      },
    );
  }
}
