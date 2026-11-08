class DayCount {
  const DayCount({required this.date, required this.count});

  final String date;
  final int count;

  factory DayCount.fromJson(Map<String, dynamic> json) {
    return DayCount(
      date: json['date'] as String? ?? '',
      count: _asInt(json['count']),
    );
  }
}

class SubjectCoverage {
  const SubjectCoverage({
    required this.id,
    required this.name,
    required this.learntLessons,
    required this.totalLessons,
    this.totalPyqs = 0,
  });

  final String id;
  final String name;
  final int learntLessons;
  final int totalLessons;

  /// Distinct active questions on this subject's papers across every university.
  /// Matches the subject PYQ list (own uni, campus, and other universities).
  final int totalPyqs;

  factory SubjectCoverage.fromJson(Map<String, dynamic> json) {
    return SubjectCoverage(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      learntLessons: _asInt(json['learnt_lessons']),
      totalLessons: _asInt(json['total_lessons']),
      totalPyqs: _asInt(json['total_pyqs']),
    );
  }
}

class StudyProgress {
  const StudyProgress({
    required this.streak,
    required this.days7,
    required this.days30,
    required this.subjects,
  });

  final int streak;
  final List<DayCount> days7;
  final List<DayCount> days30;
  final List<SubjectCoverage> subjects;

  factory StudyProgress.fromJson(Map<String, dynamic> json) {
    return StudyProgress(
      streak: _asInt(json['streak']),
      days7: _list(json['days7'], DayCount.fromJson),
      days30: _list(json['days30'], DayCount.fromJson),
      subjects: _list(json['subjects'], SubjectCoverage.fromJson),
    );
  }
}

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      // Nested JSON from the RPC is sometimes Map<dynamic, dynamic>
      // (decoded on another isolate). `is Map<String, dynamic>` drops those
      // rows, so the streak still shows and every subject card reads as
      // zero PYQs.
      if (item is Map) parse(Map<String, dynamic>.from(item)),
  ];
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

class SearchHits {
  const SearchHits({
    required this.subjects,
    required this.lessons,
    required this.questions,
  });

  final List<SearchHit> subjects;
  final List<SearchHit> lessons;
  final List<SearchHit> questions;

  factory SearchHits.fromJson(Map<String, dynamic> json) {
    return SearchHits(
      subjects: _hits(json['subjects'], 'subject'),
      lessons: _hits(json['lessons'], 'lesson'),
      questions: _hits(json['questions'], 'question'),
    );
  }
}

class SearchHit {
  const SearchHit({
    required this.id,
    required this.title,
    required this.kind,
    this.lessonId,
  });

  final String id;
  final String title;
  final String kind;
  final String? lessonId;
}

List<SearchHit> _hits(Object? raw, String kind) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map<String, dynamic>)
        SearchHit(
          id: item['id'] as String? ?? '',
          title: (item['name'] ?? item['question_text'] ?? '') as String,
          kind: kind,
          lessonId: item['lesson_id'] as String?,
        ),
  ];
}
