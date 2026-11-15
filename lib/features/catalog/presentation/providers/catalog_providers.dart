import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/cache_for_extension.dart';
import '../../../../core/utils/result.dart';
import '../../../auth/presentation/providers/auth_session_provider.dart';
import '../../data/catalog_repository.dart';
import '../../domain/catalog_models.dart';
import '../../domain/university_coverage.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';

part 'catalog_providers.g.dart';

@Riverpod(keepAlive: true)
Future<List<University>> universities(Ref ref) async {
  final signedIn = ref.watch(authSessionProvider);
  if (!signedIn) return const [];
  final result = await ref.watch(catalogRepositoryProvider).fetchUniversities();
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

@Riverpod(keepAlive: true)
Future<List<MbbsPhase>> mbbsPhases(Ref ref) async {
  final signedIn = ref.watch(authSessionProvider);
  if (!signedIn) return const [];
  final result = await ref.watch(catalogRepositoryProvider).fetchPhases();
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

@Riverpod(keepAlive: true)
Future<List<College>> colleges(Ref ref, String universityId) async {
  final signedIn = ref.watch(authSessionProvider);
  if (!signedIn) return const [];
  final result = await ref
      .watch(catalogRepositoryProvider)
      .fetchColleges(universityId);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

@riverpod
Future<List<CatalogSubject>> phaseSubjects(Ref ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  // Home follows the year saved on the profile — no in-app year switcher.
  final phaseId = (await ref.watch(userProfileProvider.future))?.mbbsPhaseId;
  final result = await ref
      .watch(catalogRepositoryProvider)
      .fetchSubjects(phaseId: phaseId);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

@riverpod
Future<List<CatalogTopic>> subjectTopics(Ref ref, String subjectId) async {
  ref.cacheFor(const Duration(minutes: 5));
  final result = await ref
      .watch(catalogRepositoryProvider)
      .fetchTopics(subjectId);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

@riverpod
Future<List<CatalogLesson>> topicLessons(Ref ref, String topicId) async {
  ref.cacheFor(const Duration(minutes: 5));
  final result = await ref
      .watch(catalogRepositoryProvider)
      .fetchLessons(topicId);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

@riverpod
Future<UniversityCoverage> universityCoverage(Ref ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final profile = await ref.watch(userProfileProvider.future);
  final universityId = profile?.universityId;
  if (universityId == null || universityId.isEmpty) {
    return const UniversityCoverage(
      paperCount: 0,
      pyqCount: 0,
      contentUniversityId: '',
    );
  }
  final unis = await ref.watch(universitiesProvider.future);
  University? selected;
  for (final u in unis) {
    if (u.id == universityId) {
      selected = u;
      break;
    }
  }
  final result = await ref
      .watch(catalogRepositoryProvider)
      .fetchCoverage(universityId, university: selected);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

@riverpod
Future<CatalogLesson?> lessonDetail(Ref ref, String lessonId) async {
  final result = await ref
      .watch(catalogRepositoryProvider)
      .fetchLesson(lessonId);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}
