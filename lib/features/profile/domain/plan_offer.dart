/// One row from `plans`. Display and practice caps come from here.
///
/// Postgres still decides what a student can open. This object is not a grant.
class PlanOffer {
  const PlanOffer({
    required this.id,
    required this.code,
    required this.name,
    this.tagline,
    required this.benefits,
    required this.amountPaise,
    this.durationMonths,
    this.durationLabel,
    required this.maxRegisteredDevices,
    this.promoHeadline,
    this.promoDetail,
    this.featuredDiscountCode,
    required this.isPublic,
    required this.isActive,
    required this.sortOrder,
    required this.contentDepth,
    required this.accessMode,
    required this.allowPractice,
    required this.allowTutorMode,
    required this.allowExamMode,
    this.maxPracticeSessionQuestions,
    this.dailyPracticeQuestionQuota,
    required this.allowTimerToggle,
    required this.allowTagFilter,
    required this.allowDifficultyFilter,
    required this.allowNegativeMarkingToggle,
  });

  final String id;
  final String code;
  final String name;
  final String? tagline;
  final List<String> benefits;
  final int amountPaise;
  final int? durationMonths;
  final String? durationLabel;
  final int maxRegisteredDevices;
  final String? promoHeadline;
  final String? promoDetail;
  final String? featuredDiscountCode;
  final bool isPublic;
  final bool isActive;
  final int sortOrder;
  final String contentDepth;
  final String accessMode;
  final bool allowPractice;
  final bool allowTutorMode;
  final bool allowExamMode;
  final int? maxPracticeSessionQuestions;
  final int? dailyPracticeQuestionQuota;
  final bool allowTimerToggle;
  final bool allowTagFilter;
  final bool allowDifficultyFilter;
  final bool allowNegativeMarkingToggle;

  bool get isPurchasable =>
      isActive &&
      isPublic &&
      amountPaise >= 100 &&
      (durationMonths ?? 0) >= 1;

  bool get allowsFullExplanation => contentDepth == 'explanation';

  String get priceLabel {
    if (amountPaise <= 0) return 'Free';
    final rupees = amountPaise / 100;
    final whole = rupees == rupees.roundToDouble();
    final text = whole ? rupees.toStringAsFixed(0) : rupees.toStringAsFixed(2);
    return '₹$text';
  }

  String get durationText {
    final label = durationLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    final months = durationMonths;
    if (months == null) return 'No expiry';
    return '$months months';
  }

  String? get promoLine {
    final headline = promoHeadline?.trim();
    if (headline == null || headline.isEmpty) return null;
    final detail = promoDetail?.trim();
    if (detail == null || detail.isEmpty) return headline;
    return '$headline · $detail';
  }

  factory PlanOffer.fromJson(Map<String, dynamic> json) {
    return PlanOffer(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? 'Plan',
      tagline: json['tagline'] as String?,
      benefits: _strings(json['benefits']),
      amountPaise: _int(json['amount_paise']),
      durationMonths: _nullableInt(json['duration_months']),
      durationLabel: json['duration_label'] as String?,
      maxRegisteredDevices: _int(json['max_registered_devices'], fallback: 1),
      promoHeadline: json['promo_headline'] as String?,
      promoDetail: json['promo_detail'] as String?,
      featuredDiscountCode: json['featured_discount_code'] as String?,
      isPublic: json['is_public'] == true,
      isActive: json['is_active'] != false,
      sortOrder: _int(json['sort_order']),
      contentDepth: json['content_depth'] as String? ?? 'explanation',
      accessMode: json['access_mode'] as String? ?? 'filtered',
      allowPractice: json['allow_practice'] == true,
      allowTutorMode: json['allow_tutor_mode'] == true,
      allowExamMode: json['allow_exam_mode'] == true,
      maxPracticeSessionQuestions: _nullableInt(
        json['max_practice_session_questions'],
      ),
      dailyPracticeQuestionQuota: _nullableInt(
        json['daily_practice_question_quota'],
      ),
      allowTimerToggle: json['allow_timer_toggle'] == true,
      allowTagFilter: json['allow_tag_filter'] == true,
      allowDifficultyFilter: json['allow_difficulty_filter'] == true,
      allowNegativeMarkingToggle: json['allow_negative_marking_toggle'] == true,
    );
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item != null && item.toString().trim().isNotEmpty)
          item.toString().trim(),
    ];
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    return _int(value);
  }
}
