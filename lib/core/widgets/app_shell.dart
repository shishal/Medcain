import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/comic_colors.dart';
import '../theme/spacing.dart';

/// Pill bottom bar: Home / Practice / Profile.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.quiz_outlined, Icons.quiz_rounded, 'Practice'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final comic = ComicColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final index = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          Spacing.md,
          0,
          Spacing.md,
          Spacing.sm,
        ),
        child: Material(
          color: comic.sticker,
          elevation: 8,
          shadowColor: comic.shadow,
          surfaceTintColor: scheme.primary.withValues(alpha: 0.08),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.xs,
            ),
            child: Row(
              children: [
                for (var i = 0; i < _destinations.length; i++)
                  Expanded(
                    child: _NavItem(
                      outlined: _destinations[i].$1,
                      filled: _destinations[i].$2,
                      label: _destinations[i].$3,
                      selected: i == index,
                      color: scheme.primary,
                      muted: scheme.onSurfaceVariant,
                      onTap: () => navigationShell.goBranch(
                        i,
                        initialLocation: i == index,
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.outlined,
    required this.filled,
    required this.label,
    required this.selected,
    required this.color,
    required this.muted,
    required this.onTap,
  });

  final IconData outlined;
  final IconData filled;
  final String label;
  final bool selected;
  final Color color;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? color : muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.xs,
              ),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.22) : null,
                borderRadius: BorderRadius.circular(999),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Icon(selected ? filled : outlined, color: fg, size: 22),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
