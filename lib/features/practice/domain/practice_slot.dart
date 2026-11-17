import '../../../core/supabase/tables.dart';
import '../../tests/domain/attempt_status.dart';
import 'practice_enums.dart';

/// The student's single practice `tests` row, if they have one.
///
/// Postgres allows only one (`tests_one_practice_per_user`). Resume while
/// [isOpen] is true. Starting again replaces the row.
class PracticeSlot {
  const PracticeSlot({
    required this.testId,
    required this.feedbackTiming,
    this.attemptId,
    this.attemptStatus,
  });

  final String testId;
  final FeedbackTiming feedbackTiming;
  final String? attemptId;
  final AttemptStatus? attemptStatus;

  /// Tutor or Exam still in progress (or not started), or a reading session.
  ///
  /// A submitted attempt is finished: the next Start replaces it with no
  /// resume. Reading never creates an attempt, so that row stays open until
  /// the student starts a new session.
  bool get isOpen {
    if (attemptStatus == AttemptStatus.submitted ||
        attemptStatus == AttemptStatus.abandoned) {
      return false;
    }
    return true;
  }

  bool get opensReader => feedbackTiming == FeedbackTiming.reading;

  /// `tests` row plus an embedded `attempts` list from PostgREST.
  factory PracticeSlot.fromTestRow(Map<String, dynamic> row) {
    final attempt = _preferredAttempt(_attemptMaps(row[Tables.attempts]));
    final statusRaw = attempt?[AttemptColumns.status] as String?;
    return PracticeSlot(
      testId: row[TestColumns.id] as String,
      feedbackTiming: FeedbackTiming.fromString(
        row[TestColumns.feedbackTiming] as String? ??
            FeedbackTiming.onSubmit.dbValue,
      ),
      attemptId: attempt?[AttemptColumns.id] as String?,
      attemptStatus: statusRaw == null
          ? null
          : AttemptStatus.fromString(statusRaw),
    );
  }
}

List<Map<String, dynamic>> _attemptMaps(Object? raw) {
  if (raw is List) {
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          item
        else if (item is Map)
          item.cast<String, dynamic>(),
    ];
  }
  if (raw is Map<String, dynamic>) return [raw];
  if (raw is Map) return [raw.cast<String, dynamic>()];
  return const [];
}

/// In-progress wins. Otherwise the attempt that started most recently.
Map<String, dynamic>? _preferredAttempt(List<Map<String, dynamic>> attempts) {
  if (attempts.isEmpty) return null;
  for (final row in attempts) {
    if (row[AttemptColumns.status] == AttemptStatus.inProgress.dbValue) {
      return row;
    }
  }
  final sorted = [...attempts]
    ..sort((a, b) {
      final aTime = DateTime.tryParse('${a[AttemptColumns.startedAt]}');
      final bTime = DateTime.tryParse('${b[AttemptColumns.startedAt]}');
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
  return sorted.first;
}
