import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medico/features/catalog/domain/catalog_models.dart';
import 'package:medico/features/catalog/presentation/widgets/year_picker.dart';

void main() {
  testWidgets('year chips fit without horizontal scroll or overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const phases = [
      MbbsPhase(id: 'p1', code: 'Y1', name: '1st year', displayOrder: 1),
      MbbsPhase(id: 'p2', code: 'Y2', name: '2nd year', displayOrder: 2),
      MbbsPhase(id: 'p3', code: 'Y3', name: '3rd year', displayOrder: 3),
      MbbsPhase(id: 'p4', code: 'Y4', name: 'Final year', displayOrder: 4),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: YearPickerRow(
              phases: phases,
              selectedId: 'p1',
              onSelect: (_) {},
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsNothing);
    expect(find.byKey(const ValueKey('year-chip-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('year-chip-p4')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('year-chip-p4'))).right,
      lessThanOrEqualTo(360),
    );
  });
}
