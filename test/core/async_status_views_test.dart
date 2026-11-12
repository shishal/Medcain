import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/utils/user_facing_error.dart';
import 'package:medico/core/widgets/async_status_views.dart';
import 'package:medico/core/widgets/brand_pulse_loader.dart';

void main() {
  testWidgets('AsyncLoadingView shows a spinner', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AsyncLoadingView())),
    );

    expect(find.byType(BrandPulseLoader), findsOneWidget);
  });

  testWidgets('AsyncErrorView shows offline copy and Retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncErrorView(
            message: UserFacingError.offlineMessage,
            onAction: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.text(UserFacingError.offlineMessage), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('AsyncEmptyView shows the empty copy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AsyncEmptyView(message: 'No bookmarks yet.')),
      ),
    );

    expect(find.text('No bookmarks yet.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
