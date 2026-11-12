import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../../core/widgets/coverage_ring.dart';
import '../../domain/attempt_results.dart';

/// Score, accuracy, percentile, time spent, and subject-wise counts.
class ResultsSummary extends StatelessWidget {
  const ResultsSummary({super.key, required this.results});

  final AttemptResults results;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Text(
          results.testTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: Spacing.lg),
        _ScoreHero(results: results),
        const SizedBox(height: Spacing.md),
        _CountRow(results: results),
        const SizedBox(height: Spacing.lg),
        _StatGrid(results: results),
        const SizedBox(height: Spacing.xl),
        Text('Subject-wise', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Spacing.sm),
        if (results.subjects.isEmpty)
          Text(
            'No subject breakdown for this test.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final row in results.subjects) ...[
            _SubjectRow(row: row),
            const SizedBox(height: Spacing.sm),
          ],
      ],
    );
  }
}

class _ScoreHero extends StatelessWidget {
  const _ScoreHero({required this.results});

  final AttemptResults results;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final showScore = results.usesNeetStyleScore;
    // Display fraction from server-stored score / max — not a new scoring pass.
    final ringProgress = showScore
        ? (results.maxScore == 0 ? 0.0 : results.totalScore / results.maxScore)
        : results.accuracyPercent / 100;

    return ComicCard(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        children: [
          CoverageRing(
            progress: ringProgress.clamp(0.0, 1.0),
            size: 132,
            strokeWidth: 10,
            child: Text(
              showScore ? results.scoreLabel : results.accuracyLabel,
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            showScore ? 'Score out of ${results.maxScoreLabel}' : 'Accuracy',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.results});

  final AttemptResults results;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CountChip(
            label: 'Correct',
            value: results.correctCount,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: _CountChip(
            label: 'Incorrect',
            value: results.incorrectCount,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: _CountChip(
            label: 'Skipped',
            value: results.unattemptedCount,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ComicCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.md,
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: textTheme.headlineSmall?.copyWith(color: color),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.results});

  final AttemptResults results;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (results.usesNeetStyleScore)
          _StatRow(label: 'Accuracy', value: results.accuracyLabel),
        if (!results.isEphemeralPractice && results.percentileLabel != null)
          _StatRow(label: 'Percentile', value: results.percentileLabel!),
        _StatRow(label: 'Time spent', value: results.timeSpentLabel),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textTheme.bodyLarge)),
          Text(value, style: textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.row});

  final SubjectBreakdown row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return ComicCard(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.subjectName, style: textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(
            '${row.correctCount} correct · '
            '${row.incorrectCount} incorrect · '
            '${row.unattemptedCount} skipped',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
