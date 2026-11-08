import 'package:flutter/material.dart';

import '../theme/navy_story.dart';
import '../theme/spacing.dart';

/// Full-bleed dusk sky. Put the scrolling sheet on top of this.
class NavyStoryBackdrop extends StatelessWidget {
  const NavyStoryBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: NavyStory.sky(Theme.of(context).brightness),
      ),
      child: child,
    );
  }
}

/// One-shot rise. Skips the motion when the system asks for reduced animation.
class DuskEntrance extends StatelessWidget {
  const DuskEntrance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // TweenAnimationBuilder plays once from 0 to 1. disableAnimations
    // is the Flutter flag for the system "reduce motion" setting.
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Colored dot plus a vertical rail. [last] drops the connector.
class TimelineTile extends StatelessWidget {
  const TimelineTile({
    super.key,
    required this.tone,
    required this.child,
    this.last = false,
    this.onTap,
    this.semanticLabel,
  });

  final Color tone;
  final Widget child;
  final bool last;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: tone,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!last)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [NavyStory.railStart, NavyStory.railEnd],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: last ? 0 : Spacing.md),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (semanticLabel == null) return tile;
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: tile,
    );
  }
}
