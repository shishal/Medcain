import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/supabase/tables.dart';
import 'package:medico/features/practice/domain/practice_enums.dart';
import 'package:medico/features/practice/domain/practice_slot.dart';
import 'package:medico/features/tests/domain/attempt_status.dart';

void main() {
  test(
    'fromTestRow prefers an in-progress attempt over a newer submitted one',
    () {
      final slot = PracticeSlot.fromTestRow({
        TestColumns.id: 'test-1',
        TestColumns.feedbackTiming: 'immediate',
        Tables.attempts: [
          {
            AttemptColumns.id: 'submitted',
            AttemptColumns.status: 'submitted',
            AttemptColumns.startedAt: '2026-11-17T12:00:00Z',
          },
          {
            AttemptColumns.id: 'open',
            AttemptColumns.status: 'in_progress',
            AttemptColumns.startedAt: '2026-11-17T10:00:00Z',
          },
        ],
      });

      expect(slot.testId, 'test-1');
      expect(slot.feedbackTiming, FeedbackTiming.immediate);
      expect(slot.attemptId, 'open');
      expect(slot.attemptStatus, AttemptStatus.inProgress);
      expect(slot.isOpen, isTrue);
      expect(slot.opensReader, isFalse);
    },
  );

  test('reading with no attempt stays open, submitted does not', () {
    final reading = PracticeSlot.fromTestRow({
      TestColumns.id: 'read-1',
      TestColumns.feedbackTiming: 'reading',
    });
    expect(reading.isOpen, isTrue);
    expect(reading.opensReader, isTrue);
    expect(reading.attemptId, isNull);

    final submitted = const PracticeSlot(
      testId: 'done',
      feedbackTiming: FeedbackTiming.onSubmit,
      attemptStatus: AttemptStatus.submitted,
    );
    expect(submitted.isOpen, isFalse);
  });
}
