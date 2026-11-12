import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../domain/attempt_review.dart';
import 'review_option_list.dart';

/// Stem, options, and solution for one review item.
class ReviewQuestionView extends StatelessWidget {
  const ReviewQuestionView({super.key, required this.item});

  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    if (item.isPlanLocked) {
      return const _PlanLockedBody();
    }

    final question = item.question!;
    final imageUrl = question.imageUrl?.trim();

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Text(
          'Question ${item.questionNumber}',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          question.questionText,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (imageUrl != null && imageUrl.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Spacing.sm),
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ],
        const SizedBox(height: Spacing.md),
        ReviewOptionList(item: item),
        const SizedBox(height: Spacing.md),
        ReviewStatusBanner(item: item),
      ],
    );
  }
}

class _PlanLockedBody extends StatelessWidget {
  const _PlanLockedBody();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: colorScheme.primary),
            const SizedBox(height: Spacing.md),
            Text(
              'This question is not available on your current plan.',
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Upgrade to see the question, your answer, and the solution.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: () => context.push(AppRoutes.upgrade),
              child: const Text('Upgrade'),
            ),
          ],
        ),
      ),
    );
  }
}
