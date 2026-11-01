import 'package:flutter/material.dart';

import '../../../../core/theme/brand_assets.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../../core/widgets/staggered_fade.dart';
import '../../domain/catalog_models.dart';

/// Compact year chips with year art inside. Used on onboarding and Profile.
class YearPickerRow extends StatelessWidget {
  const YearPickerRow({
    super.key,
    required this.phases,
    required this.selectedId,
    required this.onSelect,
    this.padding = const EdgeInsets.symmetric(horizontal: Spacing.lg),
  });

  final List<MbbsPhase> phases;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // Equal-width chips in one row — no horizontal scroll from 1st → final.
    return Padding(
      padding: padding,
      child: SizedBox(
        height: 92,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < phases.length; i++) ...[
              if (i > 0) const SizedBox(width: Spacing.sm),
              Expanded(
                child: StaggeredFade(
                  index: i,
                  child: _YearChip(
                    phase: phases[i],
                    selected: phases[i].id == selectedId,
                    fill: ComicColors.of(context).sticker,
                    onTap: () => onSelect(phases[i].id),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _YearChip extends StatelessWidget {
  const _YearChip({
    required this.phase,
    required this.selected,
    required this.fill,
    required this.onTap,
  });

  final MbbsPhase phase;
  final bool selected;
  final Color fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ComicCard(
      key: ValueKey('year-chip-${phase.id}'),
      color: fill,
      highlighted: selected,
      padding: const EdgeInsets.all(Spacing.xs),
      semanticLabel: phase.name,
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    BrandAssets.yearArt(
                      code: phase.code,
                      name: phase.name,
                      displayOrder: phase.displayOrder,
                    ),
                    fit: BoxFit.cover,
                  ),
                  if (selected)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            phase.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.1),
          ),
        ],
      ),
    );
  }
}
