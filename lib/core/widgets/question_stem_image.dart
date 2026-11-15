import 'package:material_ui/material_ui.dart';

import '../theme/spacing.dart';

/// Shared question diagram / clinical image view across Tutor/Exam player,
/// Reading Mode, and Solution Review.
///
/// Decodes at device viewport width (`cacheWidth`) so high-res camera/scan
/// images do not blow up GPU memory, reserves height while loading to prevent
/// scroll jumps, and offers tap-to-retry when mobile data drops.
class QuestionStemImage extends StatefulWidget {
  const QuestionStemImage({super.key, required this.imageUrl});

  final String? imageUrl;

  @override
  State<QuestionStemImage> createState() => _QuestionStemImageState();
}

class _QuestionStemImageState extends State<QuestionStemImage> {
  var _retryNonce = 0;

  @override
  Widget build(BuildContext context) {
    final raw = widget.imageUrl?.trim();
    if (raw == null || raw.isEmpty) return const SizedBox.shrink();

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cacheWidth = ((screenWidth - Spacing.md * 2) * dpr)
        .round()
        .clamp(240, 2048);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Spacing.sm),
        child: Image.network(
          raw,
          key: ValueKey('$raw#$_retryNonce'),
          fit: BoxFit.contain,
          cacheWidth: cacheWidth,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              height: 168,
              alignment: Alignment.center,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(Spacing.sm),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Could not load question image.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _retryNonce++),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
