import '../../../core/supabase/tables.dart';

/// One row from `admin_search_users` / `admin_get_user`.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    this.fullName,
    this.phone,
    required this.plan,
    this.planExpiresAt,
    this.planSuspendedAt,
    this.blockedAt,
    this.blockedReason,
    this.universityId,
    this.universityName,
    this.collegeId,
    this.collegeName,
    this.batchYear,
    this.mbbsPhaseId,
    required this.isAdmin,
    this.createdAt,
  });

  final String id;
  final String email;
  final String? fullName;
  final String? phone;
  final String plan;
  final DateTime? planExpiresAt;
  final DateTime? planSuspendedAt;
  final DateTime? blockedAt;
  final String? blockedReason;
  final String? universityId;
  final String? universityName;
  final String? collegeId;
  final String? collegeName;
  final int? batchYear;
  final String? mbbsPhaseId;
  final bool isAdmin;
  final DateTime? createdAt;

  bool get isBlocked => blockedAt != null;

  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return email;
  }

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String?,
      phone: json['phone'] as String?,
      plan: json['plan'] as String? ?? 'free',
      planExpiresAt: _date(json['plan_expires_at']),
      planSuspendedAt: _date(json['plan_suspended_at']),
      blockedAt: _date(json['blocked_at']),
      blockedReason: json['blocked_reason'] as String?,
      universityId: json['university_id'] as String?,
      universityName: json['university_name'] as String?,
      collegeId: json['college_id'] as String?,
      collegeName: json['college_name'] as String?,
      batchYear: _int(json['batch_year']),
      mbbsPhaseId: json['mbbs_phase_id'] as String?,
      isAdmin: json['is_admin'] == true,
      createdAt: _date(json['created_at']),
    );
  }
}

/// Fields the admin profile form writes. Null clears that column.
class AdminProfileInput {
  const AdminProfileInput({
    required this.userId,
    this.fullName,
    this.phone,
    this.universityId,
    this.collegeId,
    this.batchYear,
    this.mbbsPhaseId,
  });

  final String userId;
  final String? fullName;
  final String? phone;
  final String? universityId;
  final String? collegeId;
  final int? batchYear;
  final String? mbbsPhaseId;
}

class AdminQuestionSummary {
  const AdminQuestionSummary({
    required this.id,
    required this.questionText,
    required this.kind,
    this.marks,
    required this.requiredPlan,
    required this.isActive,
    this.subjectName,
    required this.appearanceCount,
  });

  final String id;
  final String questionText;
  final String kind;
  final num? marks;
  final String requiredPlan;
  final bool isActive;
  final String? subjectName;
  final int appearanceCount;

  factory AdminQuestionSummary.fromJson(Map<String, dynamic> json) {
    return AdminQuestionSummary(
      id: json['id'] as String,
      questionText: json['question_text'] as String? ?? '',
      kind: json['kind'] as String? ?? 'pyq_theory',
      marks: json['marks'] as num?,
      requiredPlan: json['required_plan'] as String? ?? 'free',
      isActive: json['is_active'] != false,
      subjectName: json['subject_name'] as String?,
      appearanceCount: _int(json['appearance_count']) ?? 0,
    );
  }
}

class AdminAppearance {
  const AdminAppearance({
    required this.examPaperId,
    required this.universityId,
    required this.universityName,
    this.collegeId,
    this.collegeName,
    required this.examYear,
    this.examMonth,
    this.paperName,
    required this.examType,
  });

  final String examPaperId;
  final String universityId;
  final String universityName;
  final String? collegeId;
  final String? collegeName;
  final int examYear;
  final int? examMonth;
  final String? paperName;
  final String examType;

  String get label {
    final month = examMonth == null ? '' : '${_monthName(examMonth!)} ';
    final paper = (paperName == null || paperName!.isEmpty)
        ? ''
        : ' · $paperName';
    final college = (collegeName == null || collegeName!.isEmpty)
        ? ''
        : ' · $collegeName';
    return '$universityName$college · $month$examYear · ${_examLabel(examType)}$paper';
  }

  factory AdminAppearance.fromJson(Map<String, dynamic> json) {
    return AdminAppearance(
      examPaperId: json['exam_paper_id'] as String,
      universityId: json['university_id'] as String,
      universityName: json['university_name'] as String? ?? '',
      collegeId: json['college_id'] as String?,
      collegeName: json['college_name'] as String?,
      examYear: _int(json['exam_year']) ?? 0,
      examMonth: _int(json['exam_month']),
      paperName: json['paper_name'] as String?,
      examType: json['exam_type'] as String? ?? 'prof',
    );
  }
}

class AdminQuestionDetail {
  const AdminQuestionDetail({
    required this.id,
    required this.questionText,
    required this.kind,
    this.marks,
    required this.difficulty,
    required this.requiredPlan,
    required this.isActive,
    this.optionA,
    this.optionB,
    this.optionC,
    this.optionD,
    this.correctOption,
    this.explanationText,
    this.explanationDeep,
    this.sampleAnswer,
    this.chapterName,
    this.topicName,
    this.subjectId,
    this.subjectName,
    required this.appearances,
  });

  final String id;
  final String questionText;
  final String kind;
  final num? marks;
  final String difficulty;
  final String requiredPlan;
  final bool isActive;
  final String? optionA;
  final String? optionB;
  final String? optionC;
  final String? optionD;
  final String? correctOption;
  final String? explanationText;
  final String? explanationDeep;
  final String? sampleAnswer;
  final String? chapterName;
  final String? topicName;
  final String? subjectId;
  final String? subjectName;
  final List<AdminAppearance> appearances;

  factory AdminQuestionDetail.fromJson(Map<String, dynamic> json) {
    final rawAppearances = json['appearances'];
    return AdminQuestionDetail(
      id: json['id'] as String,
      questionText: json['question_text'] as String? ?? '',
      kind: json['kind'] as String? ?? 'pyq_theory',
      marks: json['marks'] as num?,
      difficulty: json['difficulty'] as String? ?? 'should',
      requiredPlan: json['required_plan'] as String? ?? 'free',
      isActive: json['is_active'] != false,
      optionA: json['option_a'] as String?,
      optionB: json['option_b'] as String?,
      optionC: json['option_c'] as String?,
      optionD: json['option_d'] as String?,
      correctOption: json['correct_option'] as String?,
      explanationText: json['explanation_text'] as String?,
      explanationDeep: json['explanation_deep'] as String?,
      sampleAnswer: json['sample_answer'] as String?,
      chapterName: json['chapter_name'] as String?,
      topicName: json['topic_name'] as String?,
      subjectId: json['subject_id'] as String?,
      subjectName: json['subject_name'] as String?,
      appearances: rawAppearances is List
          ? [
              for (final item in rawAppearances)
                if (item is Map)
                  AdminAppearance.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
    );
  }
}

/// Stem + optional first sitting. [sitting] is required only when creating.
class AdminQuestionInput {
  const AdminQuestionInput({
    this.id,
    required this.subjectId,
    required this.questionText,
    required this.kind,
    this.marks,
    required this.difficulty,
    required this.requiredPlan,
    required this.isActive,
    this.optionA,
    this.optionB,
    this.optionC,
    this.optionD,
    this.correctOption,
    this.explanationText,
    this.explanationDeep,
    this.sampleAnswer,
    this.chapterName,
    this.topicName,
    this.sitting,
  });

  final String? id;
  final String subjectId;
  final String questionText;
  final String kind;
  final num? marks;
  final String difficulty;
  final String requiredPlan;
  final bool isActive;
  final String? optionA;
  final String? optionB;
  final String? optionC;
  final String? optionD;
  final String? correctOption;
  final String? explanationText;
  final String? explanationDeep;
  final String? sampleAnswer;
  final String? chapterName;
  final String? topicName;
  final AdminSittingInput? sitting;

  Map<String, dynamic> toJson() {
    return {
      'id': ?id,
      'subject_id': subjectId,
      QuestionColumns.questionText: questionText,
      QuestionColumns.kind: kind,
      QuestionColumns.marks: marks,
      QuestionColumns.difficulty: difficulty,
      QuestionColumns.requiredPlan: requiredPlan,
      QuestionColumns.isActive: isActive,
      QuestionColumns.optionA: optionA,
      QuestionColumns.optionB: optionB,
      QuestionColumns.optionC: optionC,
      QuestionColumns.optionD: optionD,
      QuestionColumns.correctOption: correctOption,
      QuestionColumns.explanationText: explanationText,
      QuestionColumns.explanationDeep: explanationDeep,
      'sample_answer': sampleAnswer,
      'chapter_name': chapterName,
      'topic_name': topicName,
      'sitting': ?sitting?.toJson(),
    };
  }
}

class AdminSittingInput {
  const AdminSittingInput({
    this.examPaperId,
    this.questionId,
    required this.universityId,
    this.collegeId,
    required this.examYear,
    required this.examMonth,
    this.paperName,
    required this.examType,
  });

  final String? examPaperId;
  final String? questionId;
  final String universityId;
  final String? collegeId;
  final int examYear;
  final int examMonth;
  final String? paperName;
  final String examType;

  Map<String, dynamic> toJson() {
    return {
      'question_id': ?questionId,
      'exam_paper_id': ?examPaperId,
      ExamPaperColumns.universityId: universityId,
      ExamPaperColumns.collegeId: collegeId,
      ExamPaperColumns.examYear: examYear,
      ExamPaperColumns.examMonth: examMonth,
      ExamPaperColumns.paperName: paperName,
      ExamPaperColumns.examType: examType,
    };
  }
}

class AdminAnnouncement {
  const AdminAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    this.deepLink,
    required this.isActive,
    this.publishedAt,
    this.expiresAt,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final String? deepLink;
  final bool isActive;
  final DateTime? publishedAt;
  final DateTime? expiresAt;

  factory AdminAnnouncement.fromJson(Map<String, dynamic> json) {
    return AdminAnnouncement(
      id: json[AnnouncementColumns.id] as String,
      title: json[AnnouncementColumns.title] as String? ?? '',
      body: json[AnnouncementColumns.body] as String? ?? '',
      category: json[AnnouncementColumns.category] as String? ?? 'general',
      deepLink: json[AnnouncementColumns.deepLink] as String?,
      isActive: json[AnnouncementColumns.isActive] == true,
      publishedAt: _date(json[AnnouncementColumns.publishedAt]),
      expiresAt: _date(json[AnnouncementColumns.expiresAt]),
    );
  }
}

class AdminAnnouncementInput {
  const AdminAnnouncementInput({
    this.id,
    required this.title,
    required this.body,
    required this.category,
    this.deepLink,
    required this.isActive,
    this.expiresAt,
  });

  final String? id;
  final String title;
  final String body;
  final String category;
  final String? deepLink;
  final bool isActive;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() {
    return {
      AnnouncementColumns.id: ?id,
      AnnouncementColumns.title: title,
      AnnouncementColumns.body: body,
      AnnouncementColumns.category: category,
      AnnouncementColumns.deepLink: deepLink,
      AnnouncementColumns.isActive: isActive,
      AnnouncementColumns.expiresAt: expiresAt?.toUtc().toIso8601String(),
    };
  }
}

const adminExamTypes = <(String, String)>[
  ('prof', 'Prof'),
  ('supply', 'Supply'),
  ('pre_prof', 'Pre prof'),
  ('internal', 'Internal'),
];

const adminDifficulties = <(String, String)>[
  ('must', 'Must'),
  ('should', 'Should'),
  ('could', 'Could'),
];

const adminPlans = <(String, String)>[
  ('free', 'Free'),
  ('pro', 'Pro'),
  ('elite', 'Elite'),
];

const adminAnnouncementCategories = <(String, String)>[
  ('general', 'News'),
  ('version', 'Update'),
  ('offer', 'Offer'),
  ('payment', 'Payment'),
];

String _examLabel(String value) {
  for (final item in adminExamTypes) {
    if (item.$1 == value) return item.$2;
  }
  return value;
}

String _monthName(int month) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  if (month < 1 || month > 12) return '';
  return names[month - 1];
}

String adminMonthName(int month) => _monthName(month);

DateTime? _date(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

int? _int(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
