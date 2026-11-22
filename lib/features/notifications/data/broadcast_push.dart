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
/// signed in, and reports taps, foreground arrivals, and the FCM token.
///
/// Topic membership belongs to the app install, not the Supabase user, so
/// sign-out has to unsubscribe or the next account on this phone would still
/// receive the previous one's broadcasts. The token is saved by
/// [onToken]; this class does not call Supabase.
class BroadcastPushController {
  void Function(String path)? _onOpen;
  void Function()? _onForeground;
  Future<void> Function(String token)? _onToken;
  String? _pendingPath;
  String? _token;
  var _foregroundWaiting = false;
  var _installed = false;
  var _initFailed = false;
  var _signedIn = false;
  Future<void> _tail = Future<void>.value();
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  Future<bool>? _installing;

  set onOpen(void Function(String path)? listener) {
    _onOpen = listener;
  }

  set onForeground(void Function()? listener) {
    _onForeground = listener;
  }

  /// Called with the current FCM token while this install is signed in,
  /// including when Firebase rotates the token.
  set onToken(Future<void> Function(String token)? listener) {
    _onToken = listener;
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
  ///
  /// While signed in, also reads the FCM token and passes it to [onToken].
  Future<void> sync({required bool signedIn}) {
    if (!Platform.isAndroid) return Future<void>.value();
    return _oneAtATime(() => _syncLocked(signedIn));
  }

  /// Returns the token to delete, and stops a later refresh from saving it.
  ///
  /// Call this while the Supabase session still exists. Sign-out then
  /// removes the JWT, so the delete has to happen first.
  Future<String?> takeTokenForSignOut() {
    if (!Platform.isAndroid) return Future<String?>.value();
    return _oneAtATime(() async {
      _signedIn = false;
      var token = _token;
      _token = null;
      if ((token == null || token.isEmpty) && _installed) {
        try {
          token = await _currentToken();
        } catch (error) {
          developer.log(
            'Could not read the notification token during sign-out.',
            name: 'broadcast_push',
            error: error,
          );
          token = null;
        }
      }
      if (token == null || token.isEmpty) return null;
      return token;
    });
  }

  void dispose() {
    _onOpen = null;
    _onForeground = null;
    _onToken = null;
    _openedSub?.cancel();
    _foregroundSub?.cancel();
    _tokenSub?.cancel();
  }

  Future<void> _syncLocked(bool signedIn) async {
    _signedIn = signedIn;
    try {
      final ready = await _ensureInstalled();
      if (!ready) return;
      if (!_signedIn) {
        await _unsubscribe();
        return;
      }
      await _subscribe();
      if (!_signedIn) {
        await _unsubscribe();
        return;
      }
      final token = await _currentToken();
      if (!_signedIn || token == null || token.isEmpty) return;
      _token = token;
      final register = _onToken;
      if (register != null) await register(token);
    } catch (error) {
      developer.log(
        'Could not update the broadcast subscription.',
        name: 'broadcast_push',
        error: error,
      );
    }
  }

  /// Queues [action] behind any in-flight token work.
  ///
  /// Sign-out deletes the token. If a refresh saved it at the same time,
  /// the phone would stay on the previous account's list.
  Future<T> _oneAtATime<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
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
    _listenForTokenRefresh();
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

  /// FCM registration token for this install.
  ///
  /// `register()` reports a Firebase Installation ID. The sender addresses
  /// a phone with the registration token, so this stays on getToken.
  Future<String?> _currentToken() {
    // ignore: deprecated_member_use
    return FirebaseMessaging.instance.getToken();
  }

  void _listenForTokenRefresh() {
    if (_tokenSub != null) return;
    // ignore: deprecated_member_use
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((next) {
      unawaited(
        _oneAtATime(() async {
          if (!_signedIn || next.isEmpty) return;
          _token = next;
          final register = _onToken;
          if (register != null) await register(next);
        }),
      );
    });
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
