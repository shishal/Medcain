import 'package:flutter/material.dart';

import '../theme/navy_story.dart';
import '../theme/spacing.dart';
import 'brand_wordmark.dart';
import 'comic_mascot.dart';
import 'navy_story_widgets.dart';

/// Sign-in and sign-up share one dusk header and a rounded sheet of fields.
class DuskFormPage extends StatelessWidget {
  const DuskFormPage({
    super.key,
    required this.formKey,
    required this.mascotAsset,
    required this.title,
    required this.subtitle,
    required this.children,
    this.mascotHeroTag,
  });

  final GlobalKey<FormState> formKey;
  final String mascotAsset;
  final String? mascotHeroTag;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: NavyStory.canvas(brightness),
      body: NavyStoryBackdrop(
        child: SafeArea(
          child: Form(
            key: formKey,
            child: Column(
              children: [
                DuskEntrance(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      Spacing.lg,
                      Spacing.lg,
                      Spacing.xl,
                    ),
                    child: Column(
                      children: [
                        const BrandWordmark(
                          markSize: 36,
                          alignment: MainAxisAlignment.center,
                        ),
                        const SizedBox(height: Spacing.md),
                        ComicMascot(
                          asset: mascotAsset,
                          size: 96,
                          heroTag: mascotHeroTag,
                        ),
                        const SizedBox(height: Spacing.md),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: NavyStory.sheet(brightness),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.lg,
                        Spacing.lg,
                        Spacing.lg,
                        Spacing.md,
                      ),
                      children: children,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
