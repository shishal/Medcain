import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/widgets/markdown_copy.dart';

void main() {
  testWidgets('plain explanation text is visible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownCopy(data: 'Because mitochondria produce ATP.')),
      ),
    );

    expect(
      find.text('Because mitochondria produce ATP.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('bold markdown renders the words', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownCopy(data: 'Give **four** differences.')),
      ),
    );

    expect(find.textContaining('four', findRichText: true), findsOneWidget);
    expect(find.textContaining('Give', findRichText: true), findsOneWidget);
  });

  testWidgets('answer markdown is not selectable for copy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownCopy(data: 'Sample answer body.')),
      ),
    );

    // selectable: false uses plain Text/RichText, not SelectableText.
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('zoomable answer can enlarge text via A+', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ZoomableMarkdownCopy(data: 'Long sample answer.'),
        ),
      ),
    );

    final before = tester.widget<RichText>(
      find.text('Long sample answer.', findRichText: true),
    );
    final beforePx = before.textScaler.scale(14);

    await tester.tap(find.byIcon(Icons.text_increase));
    await tester.pump();

    final after = tester.widget<RichText>(
      find.text('Long sample answer.', findRichText: true),
    );
    expect(after.textScaler.scale(14), greaterThan(beforePx));
  });
}
