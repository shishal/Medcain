import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/auth/domain/device_session.dart';
import 'package:medico/features/auth/presentation/providers/auth_session_provider.dart';
import 'package:medico/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('phone field takes focus on tap', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    final fields = find.byType(EditableText);
    expect(fields, findsOneWidget);

    await tester.tap(fields.at(0));
    await tester.pump();
    expect(
      tester.state<EditableTextState>(fields.at(0)).widget.focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('shows a session notice without updating it during build', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(deviceSessionNoticeProvider.notifier)
        .setMessage(DeviceSessionMessages.signedInElsewhere);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text(DeviceSessionMessages.signedInElsewhere), findsOneWidget);

    await tester.pump();
    expect(container.read(deviceSessionNoticeProvider), isNull);
  });
}
