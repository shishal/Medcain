import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/auth_session_provider.dart';

part 'admin_student_preview_provider.g.dart';

/// In-memory switch so an admin can open the student screens on this phone.
///
/// A [Notifier] holds a value the rest of the app can read. This one is not
/// written to disk: killing the app starts again at `false`, so the next
/// launch opens Admin. Sign-out clears it too. Students never reach the
/// Admin control that turns it on.
@Riverpod(keepAlive: true)
class AdminStudentPreview extends _$AdminStudentPreview {
  @override
  bool build() {
    // `ref.listen` runs the callback when auth changes, without rebuilding
    // this provider just because auth was read.
    ref.listen(authSessionProvider, (previous, next) {
      if (!next) state = false;
    });
    return false;
  }

  void open() => state = true;

  void close() => state = false;
}
