import '../../../core/supabase/tables.dart';
import '../../profile/domain/plan_tier.dart';

/// Practice caps from the current `plans` row. The UI reads this so caps aren't hardcoded.
///
/// Enforcement still happens in `create_practice_session()`; this is only
/// so the builder can show and respect the same numbers.
class PlanLimits {
  const PlanLimits({
    required this.plan,
    required this.maxPracticeSessionQuestions,
    this.dailyPracticeQuestionQuota,
    required this.allowFullExplanation,
    required this.allowTimerToggle,
    required this.allowTagFilter,
    required this.allowDifficultyFilter,
    required this.allowNegativeMarkingToggle,
    this.allowPractice = true,
    this.allowTutorMode = true,
    this.allowExamMode = true,
  });

  final PlanTier plan;
  final int maxPracticeSessionQuestions;

  /// Null means unlimited daily questions.
  final int? dailyPracticeQuestionQuota;
  final bool allowFullExplanation;
  final bool allowTimerToggle;
  final bool allowTagFilter;
  final bool allowDifficultyFilter;
  final bool allowNegativeMarkingToggle;
  final bool allowPractice;
  final bool allowTutorMode;
  final bool allowExamMode;

  /// Slider ceiling when the plan has no session cap. The server does not
  /// apply this number.
  static const unlimitedSliderMax = 100;

  factory PlanLimits.fromJson(Map<String, dynamic> json) {
    return PlanLimits(
      plan: PlanTier.fromString(json[PlanLimitsColumns.plan] as String),
      maxPracticeSessionQuestions: _asInt(
        json[PlanLimitsColumns.maxPracticeSessionQuestions],
      ),
      dailyPracticeQuestionQuota: _asNullableInt(
        json[PlanLimitsColumns.dailyPracticeQuestionQuota],
      ),
      allowFullExplanation:
          json[PlanLimitsColumns.allowFullExplanation] as bool? ?? true,
      allowTimerToggle:
          json[PlanLimitsColumns.allowTimerToggle] as bool? ?? true,
      allowTagFilter: json[PlanLimitsColumns.allowTagFilter] as bool? ?? true,
      allowDifficultyFilter:
          json[PlanLimitsColumns.allowDifficultyFilter] as bool? ?? true,
      allowNegativeMarkingToggle:
          json[PlanLimitsColumns.allowNegativeMarkingToggle] as bool? ?? true,
    );
  }

  /// Practice caps from a `plans` row (`current_plan_detail`).
  factory PlanLimits.fromPlan(Map<String, dynamic> json) {
    final sessionCap = json['max_practice_session_questions'];
    return PlanLimits(
      plan: PlanTier.fromString(json['code'] as String? ?? 'free'),
      maxPracticeSessionQuestions: sessionCap == null
          ? unlimitedSliderMax
          : _asInt(sessionCap),
      dailyPracticeQuestionQuota: _asNullableInt(
        json['daily_practice_question_quota'],
      ),
      allowFullExplanation: json['content_depth'] == 'explanation',
      allowTimerToggle: json['allow_timer_toggle'] == true,
      allowTagFilter: json['allow_tag_filter'] == true,
      allowDifficultyFilter: json['allow_difficulty_filter'] == true,
      allowNegativeMarkingToggle:
          json['allow_negative_marking_toggle'] == true,
      allowPractice: json['allow_practice'] == true,
      allowTutorMode: json['allow_tutor_mode'] == true,
      allowExamMode: json['allow_exam_mode'] == true,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }

  static int? _asNullableInt(Object? value) {
    if (value == null) return null;
    return _asInt(value);
  }
}

/// Plan limits plus today's usage — what the builder needs to cap the slider.
class PracticePlanContext {
  const PracticePlanContext({
    required this.limits,
    required this.questionsUsedToday,
  });

  final PlanLimits limits;
  final int questionsUsedToday;

  /// Null when the plan has no daily cap.
  int? get remainingToday {
    final quota = limits.dailyPracticeQuestionQuota;
    if (quota == null) return null;
    final left = quota - questionsUsedToday;
    return left < 0 ? 0 : left;
  }

  bool get dailyQuotaExhausted => remainingToday == 0;

  /// Highest question count the slider should allow right now.
  int get maxSelectableQuestions {
    final sessionMax = limits.maxPracticeSessionQuestions;
    final remaining = remainingToday;
    if (remaining == null) return sessionMax;
    if (remaining < sessionMax) return remaining;
    return sessionMax;
  }
}
