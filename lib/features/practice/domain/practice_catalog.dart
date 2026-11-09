import '../../../core/supabase/tables.dart';

/// Subject / topic / tag lists for the Practice Builder.
class PracticeCatalog {
  const PracticeCatalog({
    required this.subjects,
    required this.topics,
    required this.tags,
  });

  final List<Subject> subjects;
  final List<Topic> topics;
  final List<PracticeTag> tags;

  List<Topic> topicsForSubjects(Set<String> subjectIds) {
    if (subjectIds.isEmpty) return topics;
    return topics.where((t) => subjectIds.contains(t.subjectId)).toList();
  }

  /// One group when years aren't loaded, otherwise one group per year.
  List<SubjectPhaseGroup> get subjectsByPhase {
    final sorted = [...subjects]
      ..sort((a, b) {
        final byPhase = a.phaseOrder.compareTo(b.phaseOrder);
        if (byPhase != 0) return byPhase;
        final byName = (a.phaseName ?? '').compareTo(b.phaseName ?? '');
        if (byName != 0) return byName;
        return a.displayOrder.compareTo(b.displayOrder);
      });

    final groups = <String, List<Subject>>{};
    for (final subject in sorted) {
      groups.putIfAbsent(subject.phaseName ?? '', () => []).add(subject);
    }
    return [
      for (final entry in groups.entries)
        SubjectPhaseGroup(
          phaseName: entry.key.isEmpty ? null : entry.key,
          subjects: entry.value,
        ),
    ];
  }
}

class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.displayOrder,
    this.phaseId,
    this.phaseName,
    this.phaseOrder = 0,
  });

  final String id;
  final String name;
  final int displayOrder;

  /// MBBS year this subject belongs to. Null on older rows and in tests.
  final String? phaseId;
  final String? phaseName;
  final int phaseOrder;

  factory Subject.fromJson(
    Map<String, dynamic> json, {
    String? phaseName,
    int phaseOrder = 0,
  }) {
    return Subject(
      id: json[SubjectColumns.id] as String,
      name: json[SubjectColumns.name] as String,
      displayOrder: _asInt(json[SubjectColumns.displayOrder]),
      phaseId: json[SubjectColumns.mbbsPhaseId] as String?,
      phaseName: phaseName,
      phaseOrder: phaseOrder,
    );
  }
}

/// Subjects grouped by MBBS year, in year then subject order.
class SubjectPhaseGroup {
  const SubjectPhaseGroup({required this.phaseName, required this.subjects});

  /// Null when the catalog has no year labels — the sheet says "Subjects".
  final String? phaseName;
  final List<Subject> subjects;
}

class Topic {
  const Topic({
    required this.id,
    required this.subjectId,
    required this.name,
    required this.displayOrder,
  });

  final String id;
  final String subjectId;
  final String name;
  final int displayOrder;

  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      id: json[TopicColumns.id] as String,
      subjectId: json[TopicColumns.subjectId] as String,
      name: json[TopicColumns.name] as String,
      displayOrder: _asInt(json[TopicColumns.displayOrder]),
    );
  }
}

class PracticeTag {
  const PracticeTag({required this.id, required this.name});

  final String id;
  final String name;

  /// Chip label, e.g. `#PYQ`.
  String get chipLabel => name.startsWith('#') ? name : '#$name';

  factory PracticeTag.fromJson(Map<String, dynamic> json) {
    return PracticeTag(
      id: json[TagColumns.id] as String,
      name: json[TagColumns.name] as String,
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}
