import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/admin/presentation/providers/admin_student_preview_provider.dart';
import 'package:medico/features/admin/presentation/widgets/admin_student_preview_overlay.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/domain/user_profile.dart';
import 'package:medico/features/profile/presentation/providers/user_profile_provider.dart';

UserProfile _profile({required bool isAdmin}) {
  return UserProfile(
    id: 'user-1',
    plan: PlanTier.free,
    createdAt: DateTime.utc(2026, 1, 1),
    onboardingCompletedAt: DateTime.utc(2026, 8, 1),
    isAdmin: isAdmin,
  );
}

class _ProfileStub extends UserProfileNotifier {
  _ProfileStub(this.isAdmin);

  final bool isAdmin;

  @override
  Future<UserProfile?> build() async => _profile(isAdmin: isAdmin);
}

class _PreviewOn extends AdminStudentPreview {
  @override
  bool build() => true;
}

class _PreviewOff extends AdminStudentPreview {
  @override
  bool build() => false;
}

void main() {
  testWidgets('students never see the student-view chip', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith(() => _ProfileStub(false)),
          adminStudentPreviewProvider.overrideWith(_PreviewOn.new),
        ],
        child: const MaterialApp(
          home: AdminStudentPreviewOverlay(child: Text('page')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Student view'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('admin sees the chip only while previewing', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith(() => _ProfileStub(true)),
          adminStudentPreviewProvider.overrideWith(_PreviewOff.new),
        ],
        child: const MaterialApp(
          home: AdminStudentPreviewOverlay(child: Text('page')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Student view'), findsNothing);
  });

  testWidgets('Admin button leaves student view', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith(() => _ProfileStub(true)),
          adminStudentPreviewProvider.overrideWith(_PreviewOn.new),
        ],
        child: const MaterialApp(
          home: AdminStudentPreviewOverlay(child: Text('page')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Student view'), findsOneWidget);
    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();

    expect(find.text('Student view'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });
}
