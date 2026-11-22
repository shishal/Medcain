import 'package:flutter_test/flutter_test.dart';
import 'package:medico/core/router/app_routes.dart';
import 'package:medico/features/notifications/domain/announcement_link.dart';

void main() {
  group('announcementNavigation', () {
    test('shell tabs use go', () {
      expect(announcementNavigation('/home'), AnnouncementNavigation.go);
      expect(
        announcementNavigation('/practice?from=push'),
        AnnouncementNavigation.go,
      );
    });

    test('known student paths use push', () {
      expect(announcementNavigation('/upgrade'), AnnouncementNavigation.push);
      expect(
        announcementNavigation('/notifications'),
        AnnouncementNavigation.push,
      );
      expect(announcementNavigation('/pyq/abc'), AnnouncementNavigation.push);
    });

    test('rejects admin, auth, and external paths', () {
      expect(announcementNavigation('/admin'), isNull);
      expect(announcementNavigation('/admin/announcements'), isNull);
      expect(announcementNavigation('/login'), isNull);
      expect(announcementNavigation('//evil.example'), isNull);
      expect(announcementNavigation('https://example.com'), isNull);
      expect(announcementNavigation('/unknown'), isNull);
    });
  });

  group('pathFromPushData', () {
    test('uses an allowed deep link', () {
      expect(pathFromPushData({'deep_link': '/upgrade'}), '/upgrade');
    });

    test('opens the inbox when the deep link is missing or blocked', () {
      expect(pathFromPushData({}), AppRoutes.notifications);
      expect(
        pathFromPushData({'deep_link': '/admin'}),
        AppRoutes.notifications,
      );
    });
  });
}
