/// A local notification that says a workout is still open, when the logger has
/// been sitting untouched.
///
/// This is a *local* reminder, scheduled on the device. The app has no backend
/// and no account, so there is nothing to push from — see the note in
/// CLAUDE.md. What the system provides is a fire time: hand
/// `UNUserNotificationCenter` a delay and it delivers whether the app is
/// foreground, suspended or terminated, which a Dart `Timer` cannot do because
/// iOS suspends the isolate within seconds of backgrounding.
///
/// The pending reminder is a single one, replaced each time it is rescheduled,
/// so a workout with a hundred taps still has exactly one alert waiting.
///
/// iOS only, like Apple Health: every entry point answers false off iOS and
/// [isSupported] gates the UI. Android's equivalent needs its own permission
/// model and channel setup and is not implemented.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

class WorkoutReminder {
  const WorkoutReminder();

  static const _channel = MethodChannel('forma/reminders');

  /// How long the logger may sit untouched before the reminder fires.
  static const idleAfter = Duration(minutes: 30);

  /// True where reminders are implemented at all.
  static bool get isSupported => Platform.isIOS;

  /// Asks for notification permission. False if refused, or off iOS.
  ///
  /// iOS only prompts once per install; afterwards this returns the standing
  /// answer without showing anything.
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    return await _invoke<bool>('requestPermission') ?? false;
  }

  /// Whether notifications are currently allowed — the user can revoke them in
  /// iOS Settings long after saying yes here.
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    return await _invoke<bool>('hasPermission') ?? false;
  }

  /// Arms (or re-arms) the reminder for [idleAfter] from now.
  ///
  /// Called again on every interaction, which replaces the pending alert and so
  /// pushes it out another half hour. Cheap enough to call freely; the logger
  /// still throttles it rather than hitting the channel on every tap.
  Future<void> scheduleIdleReminder() async {
    if (!isSupported) return;
    await _invoke<bool>('schedule', {
      'seconds': idleAfter.inSeconds.toDouble(),
      'title': 'Workout still in progress',
      'body':
          'Forma has had a workout open for ${idleAfter.inMinutes} minutes '
          'without a change. Open it to finish and save, or discard it.',
    });
  }

  /// Drops the pending reminder, and any already delivered.
  ///
  /// Saving or discarding a workout must clear it — a reminder that a finished
  /// session is "still in progress" is worse than no reminder at all.
  Future<void> cancel() async {
    if (!isSupported) return;
    await _invoke<bool>('cancel');
  }

  /// Every call fails soft: a reminder is a convenience, and no failure here
  /// may reach the user mid-workout. It is still logged, so a channel that is
  /// silently doing nothing can be told from one that works.
  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (e) {
      debugPrint('[reminder] $method failed: $e');
      return null;
    }
  }
}
