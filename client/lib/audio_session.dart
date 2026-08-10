/// Hands the iOS audio session back once the rest chime has finished.
///
/// The chime plays with a `duckOthers` focus so it is heard over the user's
/// music without stopping it. Ducking lasts as long as the session is active,
/// and `audioplayers` never deactivates it — its single `setActive` call fires
/// on completion while the player still reports itself playing, so it
/// re-activates instead. The music therefore stays turned down until iOS
/// reclaims the session on its own, minutes later or when the app is
/// backgrounded.
///
/// [AudioSession.deactivate] is the missing half: it releases the session so
/// the duck lifts as soon as the chime ends.
///
/// iOS only. Everywhere else this is a no-op — `duckOthers` maps to Android's
/// transient-may-duck focus, which the platform releases itself.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

class AudioSession {
  const AudioSession._();

  static const _channel = MethodChannel('forma/audio_session');

  /// Releases the audio session, un-ducking whatever else is playing.
  ///
  /// Safe to call when nothing is playing and safe to call twice. Deactivating
  /// while the tail of a sound is still audible throws `is busy` on iOS, so one
  /// retry follows a short pause; anything past that is left to the system,
  /// which costs a little more ducking and nothing else.
  ///
  /// Fails soft — a stuck audio session must never surface as an error over a
  /// workout in progress — but says so, since a silently failing deactivate is
  /// indistinguishable from a working one.
  static Future<void> deactivate() async {
    if (!Platform.isIOS) return;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      try {
        await _channel.invokeMethod<bool>('deactivate');
        return;
      } catch (e) {
        debugPrint('[audio] deactivate failed (attempt ${attempt + 1}): $e');
      }
    }
  }
}
