import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps an `autoDispose` provider alive for [duration] after its last listener
/// unsubscribes, so back-navigation and `PageView` swipes feel instant without
/// holding memory for the whole app session.
extension CacheForExtension on Ref {
  void cacheFor(Duration duration) {
    final link = keepAlive();
    final timer = Timer(duration, link.close);
    onDispose(timer.cancel);
  }
}
