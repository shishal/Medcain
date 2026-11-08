import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';

/// Ordered question ids for swiping between answers.
class PyqReaderSequence {
  PyqReaderSequence(List<String> questionIds)
    : questionIds = List<String>.unmodifiable(questionIds);

  final List<String> questionIds;
}

/// Opens the PYQ reader on [questionId].
///
/// [questionIds] is the list order on the screen the student tapped, including
/// [questionId]. Two or more ids let the reader swipe to the next and previous
/// question. One id opens that question on its own.
void openPyqReader(
  BuildContext context, {
  required String questionId,
  List<String> questionIds = const [],
}) {
  final ids = [
    for (final id in questionIds)
      if (id.isNotEmpty) id,
  ];
  context.push(
    AppRoutes.pyqPath(questionId),
    extra: ids.length > 1 && ids.contains(questionId)
        ? PyqReaderSequence(ids)
        : null,
  );
}
