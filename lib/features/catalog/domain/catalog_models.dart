import '../../../core/supabase/tables.dart';
import '../../profile/domain/plan_tier.dart';

class University {
  const University({
    required this.id,
    required this.code,
    required this.name,
    required this.state,
    required this.slug,
  });

  final String id;
  final String code;
  final String name;
  final String state;
  final String slug;

  factory University.fromJson(Map<String, dynamic> json) {
    return University(
      id: json[UniversityColumns.id] as String,
      code: json[UniversityColumns.code] as String,
      name: json[UniversityColumns.name] as String,
      state: json[UniversityColumns.state] as String? ?? '',
      slug: json[UniversityColumns.slug] as String? ?? '',
    );
  }

  // Value equality by id so the picker checkmark matches the selected row.
  @override
  bool operator ==(Object other) => other is University && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Distinct states that have at least one university in the catalog, A–Z.
///
/// State is a column on [University], not a separate table — the picker
/// is just this list, then [universitiesInState] for the next field.
List<String> statesWithUniversities(List<University> universities) {
  final states = {
    for (final university in universities)
      if (university.state.isNotEmpty) university.state,
  }.toList()..sort();
  return states;
}

/// Universities in [state], or empty until a state is chosen.
List<University> universitiesInState(
  List<University> universities,
  String? state,
) {
  if (state == null || state.isEmpty) return const [];
  return [
    for (final university in universities)
      if (university.state == state) university,
  ];
}

class MbbsPhase {
  const MbbsPhase({
    required this.id,
    required this.code,
    required this.name,
    required this.displayOrder,
  });

  final String id;
  final String code;
  final String name;
  final int displayOrder;

  factory MbbsPhase.fromJson(Map<String, dynamic> json) {
    return MbbsPhase(
      id: json[MbbsPhaseColumns.id] as String,
      code: json[MbbsPhaseColumns.code] as String,
      name: json[MbbsPhaseColumns.name] as String,
      displayOrder: _asInt(json[MbbsPhaseColumns.displayOrder]),
    );
  }
}

class College {
  const College({
    required this.id,
    required this.universityId,
    required this.name,
    required this.shortForm,
  });

  final String id;
  final String universityId;
  final String name;

  /// Campus short form from the catalog, e.g. `MAMC`. Same role as
  /// [University.code].
  final String shortForm;

  /// Picker text. Same shape as a university row: `MAMC · Maulana Azad…`.
  String get label => shortForm.isEmpty ? name : '$shortForm · $name';

  factory College.fromJson(Map<String, dynamic> json) {
    return College(
      id: json[CollegeColumns.id] as String,
      universityId: json[CollegeColumns.universityId] as String,
      name: json[CollegeColumns.name] as String,
      shortForm: json[CollegeColumns.shortForm] as String? ?? '',
    );
  }
}

class CatalogSubject {
  const CatalogSubject({
    required this.id,
    required this.name,
    required this.displayOrder,
    this.mbbsPhaseId,
    this.requiredPlan = PlanTier.free,
  });

  final String id;
  final String name;
  final int displayOrder;
  final String? mbbsPhaseId;
  final PlanTier requiredPlan;

  factory CatalogSubject.fromJson(Map<String, dynamic> json) {
    return CatalogSubject(
      id: json[SubjectColumns.id] as String,
      name: json[SubjectColumns.name] as String,
      displayOrder: _asInt(json[SubjectColumns.displayOrder]),
      mbbsPhaseId: json[SubjectColumns.mbbsPhaseId] as String?,
      requiredPlan: PlanTier.fromString(
        json[SubjectColumns.requiredPlan] as String? ?? 'free',
      ),
    );
  }
}

class CatalogTopic {
  const CatalogTopic({
    required this.id,
    required this.subjectId,
    required this.name,
    required this.displayOrder,
  });

  final String id;
  final String subjectId;
  final String name;
  final int displayOrder;

  factory CatalogTopic.fromJson(Map<String, dynamic> json) {
    return CatalogTopic(
      id: json[TopicColumns.id] as String,
      subjectId: json[TopicColumns.subjectId] as String,
      name: json[TopicColumns.name] as String,
      displayOrder: _asInt(json[TopicColumns.displayOrder]),
    );
  }
}

class CatalogLesson {
  const CatalogLesson({
    required this.id,
    required this.topicId,
    required this.name,
    required this.displayOrder,
    required this.requiredPlan,
    required this.isActive,
  });

  final String id;
  final String topicId;
  final String name;
  final int displayOrder;
  final PlanTier requiredPlan;
  final bool isActive;

  factory CatalogLesson.fromJson(Map<String, dynamic> json) {
    return CatalogLesson(
      id: json[LessonColumns.id] as String,
      topicId: json[LessonColumns.topicId] as String,
      name: json[LessonColumns.name] as String,
      displayOrder: _asInt(json[LessonColumns.displayOrder]),
      requiredPlan: PlanTier.fromString(
        json[LessonColumns.requiredPlan] as String? ?? 'free',
      ),
      isActive: json[LessonColumns.isActive] as bool? ?? true,
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
