/// Apple Health integration: mirrors finished workouts into Health and reads
/// back what the watch measured over the session.
///
/// The app has no network layer and this doesn't add one — HealthKit is a local
/// store on the device. What it does add is a dependency on data the app does
/// not own: readings can be absent, late, or revoked at any time, so every
/// method here fails soft and returns null rather than throwing into the UI.
///
/// iOS only by design. Android's equivalent is Health Connect, a separate API
/// with its own permission model; every entry point here answers false or null
/// off iOS so the rest of the app needs no platform checks.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:health/health.dart';

/// What the watch recorded over a session's window.
class HealthMetrics {
  const HealthMetrics({this.activeEnergy, this.avgHeartRate, this.maxHeartRate});

  /// Kilocalories of active energy.
  final double? activeEnergy;
  final int? avgHeartRate;
  final int? maxHeartRate;

  bool get isEmpty =>
      activeEnergy == null && avgHeartRate == null && maxHeartRate == null;
}

class HealthSync {
  HealthSync({Health? health}) : _health = health ?? Health();

  final Health _health;

  /// Energy and heart rate are read; workouts are both read (to spot one we
  /// already wrote) and written.
  ///
  /// Each type appears exactly once. Listing WORKOUT twice — once READ, once
  /// WRITE — registers only one of them, and the write access is the one that
  /// goes missing.
  static const _types = [
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.HEART_RATE,
    HealthDataType.WORKOUT,
  ];
  static const _access = [
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ_WRITE,
  ];

  /// True where Health exists at all — everywhere but iOS this is false and the
  /// feature stays hidden.
  static bool get isSupported => Platform.isIOS;

  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Asks for the permissions the feature needs, returning whether they were
  /// granted.
  ///
  /// Called when the user switches sync on, so the system prompt is a response
  /// to something they did rather than a surprise at launch.
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;
    try {
      await _ensureConfigured();
      return await _health.requestAuthorization(_types, permissions: _access);
    } catch (e) {
      debugPrint('[health] authorization failed: $e');
      return false;
    }
  }

  /// Whether Health will accept a workout from us.
  ///
  /// iOS reports write permission truthfully; read permission is deliberately
  /// opaque for privacy, so this only speaks for writing.
  Future<bool> canWriteWorkouts() async {
    if (!isSupported) return false;
    try {
      await _ensureConfigured();
      return await _health.hasPermissions(
            [HealthDataType.WORKOUT],
            permissions: [HealthDataAccess.WRITE],
          ) ??
          false;
    } catch (e) {
      debugPrint('[health] permission check failed: $e');
      return false;
    }
  }

  /// Saves a finished session to Health as strength training, so it appears in
  /// the Fitness app and is visible to other health apps.
  ///
  /// Returns null on success or a short reason on failure — callers may choose
  /// to ignore it, but it must be *available*, because a silently swallowed
  /// failure here is indistinguishable from Health simply being quiet.
  ///
  /// Energy is deliberately not written: the watch is already recording active
  /// energy for this period, and writing our own would double-count it.
  ///
  /// The activity type must be [HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING].
  /// `STRENGTH_TRAINING` is Android-only in this plugin and throws on iOS.
  Future<String?> writeWorkout({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!isSupported) return 'Apple Health is only available on iOS.';
    if (!end.isAfter(start)) return 'The session has no duration.';
    try {
      await _ensureConfigured();
      final ok = await _health.writeWorkoutData(
        activityType:
            HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
        start: start,
        end: end,
        title: 'Forma',
      );
      if (!ok) {
        debugPrint('[health] writeWorkoutData returned false');
        return 'Apple Health refused the workout. Check that Forma may write '
            'Workouts in Settings → Health → Data Access & Devices.';
      }
      return null;
    } catch (e) {
      debugPrint('[health] write failed: $e');
      return 'Could not save to Apple Health: $e';
    }
  }

  /// Whether Health already holds a workout overlapping this window.
  ///
  /// Guards against writing a second copy — of our own earlier write, or of a
  /// session recorded on the watch itself.
  Future<bool> hasWorkoutInWindow({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!isSupported || !end.isAfter(start)) return false;
    try {
      await _ensureConfigured();
      final existing = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.WORKOUT],
        startTime: start,
        endTime: end,
      );
      return existing.isNotEmpty;
    } catch (e) {
      debugPrint('[health] workout lookup failed: $e');
      // Unknown is treated as "nothing there": failing to write is a worse
      // outcome than a duplicate the user can delete.
      return false;
    }
  }

  /// Sums active energy and summarizes heart rate over a session's window.
  ///
  /// Returns null when nothing is available — Health may simply not have synced
  /// from the watch yet, which is why the workout screen offers a refresh
  /// rather than treating the first answer as final.
  Future<HealthMetrics?> readMetrics({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!isSupported || !end.isAfter(start)) return null;
    try {
      await _ensureConfigured();
      final points = await _health.getHealthDataFromTypes(
        types: const [
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.HEART_RATE,
        ],
        startTime: start,
        endTime: end,
      );
      // The same sample can arrive from both the watch and the phone; Health's
      // deduplicator is what keeps energy from being counted twice.
      final unique = _health.removeDuplicates(points);

      var energy = 0.0;
      var sawEnergy = false;
      final beats = <double>[];
      for (final p in unique) {
        final value = p.value;
        if (value is! NumericHealthValue) continue;
        final n = value.numericValue.toDouble();
        switch (p.type) {
          case HealthDataType.ACTIVE_ENERGY_BURNED:
            energy += n;
            sawEnergy = true;
          case HealthDataType.HEART_RATE:
            beats.add(n);
          default:
            break;
        }
      }

      final metrics = HealthMetrics(
        activeEnergy: sawEnergy ? energy : null,
        avgHeartRate: beats.isEmpty
            ? null
            : (beats.reduce((a, b) => a + b) / beats.length).round(),
        maxHeartRate: beats.isEmpty
            ? null
            : beats.reduce((a, b) => a > b ? a : b).round(),
      );
      return metrics.isEmpty ? null : metrics;
    } catch (e) {
      debugPrint('[health] read failed: $e');
      return null;
    }
  }
}
