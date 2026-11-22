import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/app_routes.dart';

/// How an allowed in-app path is opened.
///
/// Shell tabs are branches of a [StatefulShellRoute], so they must use `go`.
/// Other student routes are pushed on top of the current one.
enum AnnouncementNavigation { go, push }

/// Whether [raw] is a student path the inbox already allows.
///
/// Returns null for empty, external, admin, auth, or unknown paths.
AnnouncementNavigation? announcementNavigation(String raw) {
  if (!raw.startsWith('/') || raw.startsWith('//')) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme || uri.host.isNotEmpty) return null;
  final path = uri.path;

  const shellRoutes = {AppRoutes.home, AppRoutes.practice, AppRoutes.profile};
  if (shellRoutes.contains(path)) return AnnouncementNavigation.go;

  const pushPrefixes = [
    AppRoutes.upgrade,
    AppRoutes.bookmarks,
    AppRoutes.progress,
    AppRoutes.search,
    AppRoutes.notifications,
    '/subjects/',
    '/topics/',
    '/lessons/',
    '/pyq/',
  ];
  final allowed = pushPrefixes.any(
    (prefix) => path == prefix || path.startsWith(prefix),
  );
  if (!allowed) return null;
  return AnnouncementNavigation.push;
}

/// Opens [raw] when it is an allowed student path.
void openAnnouncementPath(BuildContext context, String raw) {
  switch (announcementNavigation(raw)) {
    case AnnouncementNavigation.go:
      context.go(raw);
    case AnnouncementNavigation.push:
      context.push(raw);
    case null:
      break;
  }
}

/// Lock-screen tap target. A missing or disallowed deep link opens the inbox.
String pathFromPushData(Map<String, dynamic> data) {
  final raw = data['deep_link'];
  if (raw is String && announcementNavigation(raw) != null) return raw;
  return AppRoutes.notifications;
}
