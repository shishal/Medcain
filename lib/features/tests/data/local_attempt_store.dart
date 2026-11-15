import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/attempt_status.dart';
import '../domain/local_attempt_snapshot.dart';

part 'local_attempt_store.g.dart';

/// JSON files under app documents: `attempts/attempt_<id>.json`.
///
/// Inject [documentsDirectory] in tests so we never touch the real device
/// folder. Production uses `path_provider`.
class LocalAttemptStore {
  LocalAttemptStore({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  Future<void> write(LocalAttemptSnapshot snapshot) async {
    final file = await _fileFor(snapshot.attemptId);
    await file.writeAsString(jsonEncode(snapshot.toJson()));
  }

  Future<LocalAttemptSnapshot?> read(String attemptId) async {
    final file = await _fileFor(attemptId);
    if (!await file.exists()) return null;
    return _parseFile(file);
  }

  Future<void> delete(String attemptId) async {
    final file = await _fileFor(attemptId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Newest in-progress or pending-submit snapshot for this user+test, or null.
  ///
  /// pending_submit is included so a timer that already hit zero still
  /// auto-submits on resume instead of opening a dead countdown.
  Future<LocalAttemptSnapshot?> readOpenForTest({
    required String testId,
    required String userId,
  }) async {
    final matches = (await listForUser(userId))
        .where((s) => s.testId == testId)
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return matches.first;
  }

  /// Newest in-progress snapshot for this user+test, or null.
  Future<LocalAttemptSnapshot?> readInProgressForTest({
    required String testId,
    required String userId,
  }) async {
    final matches = (await listForUser(userId))
        .where(
          (s) =>
              s.testId == testId &&
              s.localStatus == LocalAttemptStatus.inProgress,
        )
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return matches.first;
  }

  Future<List<LocalAttemptSnapshot>> listForUser(String userId) async {
    final dir = await _attemptsDir();
    if (!await dir.exists()) return const [];

    final snapshots = <LocalAttemptSnapshot>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final snapshot = await _parseFile(entity);
      if (snapshot == null) continue;
      if (snapshot.userId != userId) continue;
      snapshots.add(snapshot);
    }
    return snapshots;
  }

  Future<void> clearAll() async {
    try {
      final dir = await _attemptsDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } on Object {
      // Best-effort cleanup on sign-out; never block logging out.
    }
  }

  Future<Directory> _attemptsDir() async {
    final root = await _documentsDirectory();
    return Directory('${root.path}/attempts');
  }

  Future<File> _fileFor(String attemptId) async {
    final dir = await _attemptsDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/attempt_$attemptId.json');
  }

  Future<LocalAttemptSnapshot?> _parseFile(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        if (decoded is Map) {
          return LocalAttemptSnapshot.fromJson(decoded.cast<String, dynamic>());
        }
        return null;
      }
      return LocalAttemptSnapshot.fromJson(decoded);
    } on FormatException {
      return null;
    } on Object {
      return null;
    }
  }
}

@Riverpod(keepAlive: true)
LocalAttemptStore localAttemptStore(Ref ref) {
  return LocalAttemptStore();
}
