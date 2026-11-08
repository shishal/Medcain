import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
