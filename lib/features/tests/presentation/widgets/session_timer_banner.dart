import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/spacing.dart';
import '../../domain/player_session_state.dart';
import '../../domain/session_timer.dart';

/// Live countdown. Rebuilds every second from wall-clock remaining time;
/// it does not decrement a stored value.
class SessionTimerBanner extends StatefulWidget {
  const SessionTimerBanner({super.key, required this.session, this.now});

  final PlayerSessionState session;
  final DateTime Function()? now;

  @override
  State<SessionTimerBanner> createState() => _SessionTimerBannerState();
}

class _SessionTimerBannerState extends State<SessionTimerBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final remaining = session.remainingAt(_now());
    if (remaining == null) return const SizedBox.shrink();

    final urgent = session.isTimerUrgentAt(_now());
    final color = urgent
        ? Theme.of(context).urgentAccent
        : Theme.of(context).colorScheme.onSurface;
    final label = formatCountdown(remaining);
    final sectionPrefix = session.isSectional
        ? 'Sec ${session.currentSection} · '
        : '';

    return Semantics(
      liveRegion: true,
      label: session.isSectional
          ? 'Section ${session.currentSection}, $label remaining'
          : '$label remaining',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 18, color: color),
            const SizedBox(width: Spacing.xs),
            Text(
              '$sectionPrefix$label',
              key: const Key('session-timer'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: urgent ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
