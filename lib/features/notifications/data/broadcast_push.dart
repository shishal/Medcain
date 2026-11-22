import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../domain/announcement_link.dart';

/// FCM topic for every signed-in Android install.
///
/// Must match `BROADCAST_TOPIC` in
/// `supabase/functions/_shared/announcement_push.ts`.
const announcementBroadcastTopic = 'broadcast';

/// Subscribes this install to [announcementBroadcastTopic] while someone is
/// signed in, and reports taps and foreground arrivals.
///
/// Topic membership belongs to the app install, not the Supabase user, so
/// sign-out has to unsubscribe or the next account on this phone would still
/// receive the previous one's broadcasts.
class BroadcastPushController {
  void Function(String path)? _onOpen;
  void Function()? _onForeground;
  String? _pendingPath;
  var _foregroundWaiting = false;
  var _installed = false;
  var _initFailed = false;
  var _generation = 0;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  Future<bool>? _installing;

  set onOpen(void Function(String path)? listener) {
    _onOpen = listener;
  }

  set onForeground(void Function()? listener) {
    _onForeground = listener;
  }

  /// Path from a tap that arrived before [onOpen] was set.
  String? takePendingPath() {
    final path = _pendingPath;
    _pendingPath = null;
    return path;
  }

  /// True when a foreground alert arrived before [onForeground] was set.
  bool takeForeground() {
    final waiting = _foregroundWaiting;
    _foregroundWaiting = false;
    return waiting;
  }

  /// Android only. iOS stays on the in-app inbox until App Store work.
  Future<void> sync({required bool signedIn}) async {
    if (!Platform.isAndroid) return;
    final generation = ++_generation;
    try {
      final ready = await _ensureInstalled();
      if (!ready || generation != _generation) return;
      if (!signedIn) {
        await _unsubscribe();
        return;
      }
      await _subscribe();
      if (generation != _generation) await _unsubscribe();
    } catch (error) {
      developer.log(
        'Could not update the broadcast subscription.',
        name: 'broadcast_push',
        error: error,
      );
    }
  }

  void dispose() {
    _onOpen = null;
    _onForeground = null;
    _openedSub?.cancel();
    _foregroundSub?.cancel();
  }

  Future<bool> _ensureInstalled() {
    final existing = _installing;
    if (existing != null) return existing;
    final future = _install();
    _installing = future;
    return future;
  }

  Future<bool> _install() async {
    if (_installed) return true;
    if (_initFailed) return false;
    try {
      // Without google-services.json this throws. The inbox still works.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (error) {
      _initFailed = true;
      _installing = Future.value(false);
      developer.log(
        'Lock-screen alerts are off until Firebase is configured.',
        name: 'broadcast_push',
        error: error,
      );
      return false;
    }

    // A notification payload is shown by Android when the app is in the
    // background. In the foreground the system stays quiet; we only refresh
    // the inbox so the bell updates.
    _foregroundSub = FirebaseMessaging.onMessage.listen(
      (_) => _emitForeground(),
    );
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _emitOpen(message.data),
    );
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _emitOpen(initial.data);
    } catch (error) {
      developer.log(
        'Could not read the notification that opened the app.',
        name: 'broadcast_push',
        error: error,
      );
    }
    _installed = true;
    return true;
  }

  Future<void> _subscribe() async {
    final messaging = FirebaseMessaging.instance;
    // The system dialog appears only until the student answers. Later calls
    // do not ask again. A denial is not a failure.
    await messaging.requestPermission(alert: true, badge: false, sound: true);
    await messaging.subscribeToTopic(announcementBroadcastTopic);
  }

  Future<void> _unsubscribe() async {
    if (!_installed) return;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(
        announcementBroadcastTopic,
      );
    } catch (error) {
      developer.log(
        'Could not leave the broadcast topic.',
        name: 'broadcast_push',
        error: error,
      );
    }
  }

  void _emitOpen(Map<String, dynamic> data) {
    final path = pathFromPushData(data);
    final listener = _onOpen;
    if (listener == null) {
      _pendingPath = path;
      return;
    }
    listener(path);
  }

  void _emitForeground() {
    final listener = _onForeground;
    if (listener == null) {
      _foregroundWaiting = true;
      return;
    }
    listener();
  }
}
