import 'package:flutter_test/flutter_test.dart';
import 'package:medico/core/supabase/tables.dart';
import 'package:medico/features/app_update/domain/app_update_policy.dart';

void main() {
  group('AppUpdatePolicy', () {
    test('parses the rpc row', () {
      final policy = AppUpdatePolicy.fromJson({
        AppUpdatePolicyColumns.minVersionCode: 28,
        AppUpdatePolicyColumns.minVersionName: '1.1.26',
        AppUpdatePolicyColumns.updatedAt: '2026-11-17T12:00:00Z',
      });

      expect(policy.minVersionCode, 28);
      expect(policy.minVersionName, '1.1.26');
      expect(policy.isEnforced, isTrue);
      expect(policy.updatedAt, isNotNull);
    });

    test('0 allows every build', () {
      expect(AppUpdatePolicy.off.blocksBuild(1), isFalse);
      expect(AppUpdatePolicy.off.blocksBuild(0), isFalse);
    });

    test('blocks only builds below the minimum', () {
      const policy = AppUpdatePolicy(
        minVersionCode: 28,
        minVersionName: '1.1.26',
      );

      expect(policy.blocksBuild(27), isTrue);
      expect(policy.blocksBuild(28), isFalse);
      expect(policy.blocksBuild(29), isFalse);
    });
  });

  group('AppUpdateVerdict.resolve', () {
    const policy = AppUpdatePolicy(
      minVersionCode: 28,
      minVersionName: '1.1.26',
    );

    test('blocks an older install', () {
      final verdict = AppUpdateVerdict.resolve(
        installedVersionCode: 27,
        policy: policy,
      );

      expect(verdict.blocked, isTrue);
      expect(verdict.requiredVersionName, '1.1.26');
    });

    test('allows the minimum build', () {
      final verdict = AppUpdateVerdict.resolve(
        installedVersionCode: 28,
        policy: policy,
      );

      expect(verdict.blocked, isFalse);
    });

    test('allows the app when no rule has ever been loaded', () {
      final verdict = AppUpdateVerdict.resolve(
        installedVersionCode: 1,
        policy: null,
      );

      expect(verdict.blocked, isFalse);
    });

    test('blocks when the install version cannot be read and a rule is on', () {
      final verdict = AppUpdateVerdict.resolve(
        installedVersionCode: null,
        policy: policy,
      );

      expect(verdict.blocked, isTrue);
    });
  });
}
