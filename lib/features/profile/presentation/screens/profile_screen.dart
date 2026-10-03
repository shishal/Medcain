import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/support.dart';
import '../../../../core/theme/brand_assets.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/open_external_link.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../../core/widgets/comic_mascot.dart';
import '../../../../core/widgets/theme_mode_selector.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/device_session.dart';
import '../providers/current_plan_provider.dart';
import '../providers/referral_code_provider.dart';
import '../providers/user_profile_provider.dart';
import '../widgets/academic_editor.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isSigningOut = false;

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);

    final result = await ref.read(authRepositoryProvider).signOut();

    if (!mounted) return;

    setState(() => _isSigningOut = false);

    switch (result) {
      case Success():
        context.go(AppRoutes.login);
      case Failure(:final message):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(currentPlanProvider);
    final profileAsync = ref.watch(userProfileProvider);

    final name = profileAsync.value?.fullName?.trim();
    final comic = ComicColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh plan',
            onPressed: () {
              ref.invalidate(ownReferralCodeProvider);
              ref.read(userProfileProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(userProfileProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            const Center(
              child: ComicMascot(
                asset: BrandAssets.mascotAvatar,
                size: 96,
                bounce: false,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              (name == null || name.isEmpty) ? 'MEDCAIN student' : name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            profileAsync.when(
              data: (profile) {
                if (profile == null) return const SizedBox.shrink();
                final unis = ref.watch(universitiesProvider).value ?? const [];
                final phases = ref.watch(mbbsPhasesProvider).value ?? const [];
                String? uniCode;
                String? yearName;
                for (final u in unis) {
                  if (u.id == profile.universityId) uniCode = u.code;
                }
                for (final p in phases) {
                  if (p.id == profile.mbbsPhaseId) yearName = p.name;
                }
                final bits = [
                  ?uniCode,
                  ?yearName,
                  if (profile.batchYear != null) '${profile.batchYear} batch',
                ];
                if (bits.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(
                    bits.join(' · '),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: Spacing.sm),
            // One plan line. This used to be "Current plan: Pro" followed by
            // "Stored plan: Pro · expires 2026-09-20 14:33:00.000".
            planAsync.when(
              data: (plan) {
                if (plan == null) return const SizedBox.shrink();
                final profile = profileAsync.value;
                final expires = profile?.planExpiresAt;
                final suspended = profile?.isPlanSuspended ?? false;
                return Column(
                  children: [
                    Text(
                      suspended ? 'Free (paused)' : plan.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (suspended) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        DeviceSessionMessages.planSuspended,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ] else if (expires != null) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        DateFormats.planExpiry(expires),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (error, _) => InlineErrorMessage(
                message: UserFacingError.display(error),
                onRetry: () => ref.read(userProfileProvider.notifier).refresh(),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            profileAsync.when(
              data: (profile) {
                if (profile == null) return const SizedBox.shrink();
                return ComicCard(child: AcademicEditor(profile: profile));
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: Spacing.lg),
            const _ReferralCodeCard(),
            ComicCard(
              color: Color.alphaBlend(
                StickerFills.mint.withValues(alpha: 0.4),
                comic.sticker,
              ),
              onTap: () => openExternalLink(context, SupportLinks.whatsAppUrl),
              child: const Row(
                children: [
                  Icon(Icons.chat_outlined),
                  SizedBox(width: Spacing.md),
                  Expanded(child: Text('WhatsApp community')),
                  Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            ComicCard(
              color: Color.alphaBlend(
                ComicColors.of(context).accentPurple.withValues(alpha: 0.18),
                comic.sticker,
              ),
              onTap: () => openExternalLink(context, SupportLinks.telegramUrl),
              child: const Row(
                children: [
                  Icon(Icons.campaign_outlined),
                  SizedBox(width: Spacing.md),
                  Expanded(child: Text('Telegram channel')),
                  Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            ComicCard(
              color: Color.alphaBlend(
                StickerFills.peach.withValues(alpha: 0.4),
                comic.sticker,
              ),
              // push, not go: otherwise Plans replaces the stack and its back
              // button falls through to Home instead of returning here.
              onTap: () => context.push(AppRoutes.upgrade),
              child: const Row(
                children: [
                  Icon(Icons.workspace_premium_outlined),
                  SizedBox(width: Spacing.md),
                  Expanded(child: Text('Compare plans')),
                  Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            const ComicCard(child: ThemeModeSelector()),
            const SizedBox(height: Spacing.md),
            TextButton(
              onPressed: _isSigningOut ? null : _signOut,
              child: _isSigningOut
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown only after a code is issued in Postgres. Copy puts it on the
/// pasteboard so the student can send it to a classmate.
class _ReferralCodeCard extends ConsumerWidget {
  const _ReferralCodeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codeAsync = ref.watch(ownReferralCodeProvider);
    final code = codeAsync.value;
    if (code == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: ComicCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your referral code', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              'Classmates get ${code.percentOff}% off at checkout. '
              'It does not discount your own payment.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    code.code,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code.code));
                    // The await can finish after the student has left Profile.
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
