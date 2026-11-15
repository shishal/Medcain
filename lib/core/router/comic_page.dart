import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

final _fadeTween = CurveTween(curve: Curves.easeOutCubic);

/// Quiet fade used instead of the comic sticker-flip (scale + slide).
CustomTransitionPage<void> comicTransitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: state.name,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // `animation.drive` attaches no disposable listener per frame (unlike
      // allocating a `CurvedAnimation` inside `transitionsBuilder`).
      return FadeTransition(
        opacity: animation.drive(_fadeTween),
        child: child,
      );
    },
  );
}

GoRoute comicGoRoute({
  required String path,
  required Widget Function(BuildContext context, GoRouterState state) builder,
}) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) =>
        comicTransitionPage(state: state, child: builder(context, state)),
  );
}
