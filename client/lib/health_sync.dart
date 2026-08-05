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

  /// Read: what the watch measured. Write: the workout itself.
  static const _readTypes = [
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.HEART_RATE,
    HealthDataType.WORKOUT,
  ];
  static const _writeTypes = [HealthDataType.WORKOUT];

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
      return await _health.requestAuthorization(
        [..._readTypes, ..._writeTypes],
        permissions: [
          ...List.filled(_readTypes.length, HealthDataAccess.READ),
          ...List.filled(_writeTypes.length, HealthDataAccess.WRITE),
        ],
      );
    } catch (_) {
      return false;
    }
  }

  /// Saves a finished session to Health as strength training, so it counts
  /// toward the activity rings and shows up alongside other exercise.
  ///
  /// Returns whether Health accepted it. Energy is deliberately not written:
  /// the watch is already recording active energy for this period, and writing
  /// our own would double-count it.
  Future<bool> writeWorkout({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!isSupported || !end.isAfter(start)) return false;
    try {
      await _ensureConfigured();
      return await _health.writeWorkoutData(
        activityType: HealthWorkoutActivityType.STRENGTH_TRAINING,
        start: start,
        end: end,
      );
    } catch (_) {
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
    } catch (_) {
      return null;
    }
  }
}
