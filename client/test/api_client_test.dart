import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forma/api_client.dart';
import 'package:forma/models.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Redirects the store at a scratch directory so tests never touch a real
/// documents folder.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  late Directory dir;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir = Directory.systemTemp.createTempSync('forma_test');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  File storeFile() => File('${dir.path}/forma_data.json');

  group('seeding', () {
    test('a fresh store comes with the default library', () async {
      final api = ApiClient();
      final exercises = await api.listExercises();
      final equipment = await api.listEquipmentTypes();

      expect(exercises, hasLength(40));
      expect(equipment, hasLength(6));
      expect(exercises.every((e) => e.isDefault), isTrue);
      expect(storeFile().existsSync(), isTrue);
    });

    test('user records never reuse a seeded id', () async {
      final api = ApiClient();
      final created = await api.createExercise(name: 'Zercher Squat');
      final seedIds = (await api.listExercises())
          .where((e) => e.isDefault)
          .map((e) => e.id);

      expect(seedIds, isNot(contains(created.id)));
      expect(created.id, greaterThan(1000));
    });

    test('restoring defaults re-adds only what was deleted', () async {
      final api = ApiClient();
      final all = await api.listExercises();
      await api.deleteExercise(all.first.id);
      await api.deleteExercise(all[1].id);

      expect(await api.restoreDefaultExercises(), 2);
      expect(await api.listExercises(), hasLength(40));
      // Nothing to restore the second time.
      expect(await api.restoreDefaultExercises(), 0);
    });
  });

  group('workouts', () {
    test('creating a workout assigns ids and renumbers sets', () async {
      final api = ApiClient();
      final workout = await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 7,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [
              WorkoutSetDraft(weight: 135, reps: 8),
              WorkoutSetDraft(weight: 145, reps: 6),
            ],
          ),
        ],
      );

      expect(workout.id, 1);
      expect(workout.exercises.single.sets.map((s) => s.setNumber), [1, 2]);
      expect(workout.setCount, 2);
      expect(workout.volume, 135 * 8 + 145 * 6);
    });

    test('deleting an exercise removes it from logged history', () async {
      final api = ApiClient();
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [WorkoutSetDraft(weight: 100, reps: 5)],
          ),
          WorkoutExerciseDraft(
            exerciseId: 2,
            sets: [WorkoutSetDraft(weight: 50, reps: 10)],
          ),
        ],
      );

      await api.deleteExercise(1);
      final workout = (await api.listWorkouts()).single;

      expect(workout.exercises, hasLength(1));
      expect(workout.exercises.single.exerciseId, 2);
    });

    test('superset grouping is persisted and read back', () async {
      final api = ApiClient();
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            supersetGroup: 1,
            sets: [WorkoutSetDraft(weight: 100, reps: 5)],
          ),
          WorkoutExerciseDraft(
            exerciseId: 2,
            supersetGroup: 1,
            sets: [WorkoutSetDraft(weight: 50, reps: 10)],
          ),
          WorkoutExerciseDraft(
            exerciseId: 3,
            sets: [WorkoutSetDraft(weight: 75, reps: 8)],
          ),
        ],
      );

      // Reopen against the same file so this exercises fromJson too.
      final workout = (await ApiClient().listWorkouts()).single;
      expect(workout.exercises[0].supersetGroup, 1);
      expect(workout.exercises[1].supersetGroup, 1);
      expect(workout.exercises[2].supersetGroup, isNull);
    });

    test('per-exercise rest is persisted and read back', () async {
      final api = ApiClient();
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            restSeconds: 120,
            sets: [WorkoutSetDraft(weight: 100, reps: 5)],
          ),
          WorkoutExerciseDraft(
            exerciseId: 2,
            sets: [WorkoutSetDraft(weight: 50, reps: 10)],
          ),
        ],
      );

      final workout = (await ApiClient().listWorkouts()).single;
      expect(workout.exercises[0].restSeconds, 120);
      // Unset defaults to 0 (no rest timer).
      expect(workout.exercises[1].restSeconds, 0);
    });

    test('merging an exercise moves its history and deletes the source',
        () async {
      final api = ApiClient();
      final dup = await api.createExercise(name: 'Bench Press');
      // Log one workout under the duplicate, one under a seed exercise (1).
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: dup.id,
            sets: [WorkoutSetDraft(weight: 135, reps: 8)],
          ),
        ],
      );
      await api.createWorkout(
        date: DateTime(2026, 7, 2),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [WorkoutSetDraft(weight: 100, reps: 5)],
          ),
        ],
      );

      await api.mergeExercise(sourceId: dup.id, targetId: 1);

      // Source gone; both sessions now belong to exercise 1.
      expect((await api.listExercises()).any((e) => e.id == dup.id), isFalse);
      expect(await api.exerciseHistory(dup.id), isEmpty);
      expect(await api.exerciseHistory(1), hasLength(2));
    });

    test('merging folds duplicate entries within one workout into one',
        () async {
      final api = ApiClient();
      final dup = await api.createExercise(name: 'Bench Press');
      // A single workout containing both the duplicate and the target.
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [WorkoutSetDraft(weight: 135, reps: 8)],
          ),
          WorkoutExerciseDraft(
            exerciseId: dup.id,
            sets: [WorkoutSetDraft(weight: 145, reps: 6)],
          ),
        ],
      );

      await api.mergeExercise(sourceId: dup.id, targetId: 1);

      final workout = (await api.listWorkouts()).single;
      expect(workout.exercises, hasLength(1));
      final entry = workout.exercises.single;
      expect(entry.exerciseId, 1);
      expect(entry.sets, hasLength(2));
      expect(entry.sets.map((s) => s.setNumber), [1, 2]);
    });

    test('history for an exercise is newest first', () async {
      final api = ApiClient();
      for (final day in [3, 1, 2]) {
        await api.createWorkout(
          date: DateTime(2026, 7, day),
          effortLevel: 5,
          exercises: [
            WorkoutExerciseDraft(
              exerciseId: 1,
              sets: [WorkoutSetDraft(weight: 100, reps: 5)],
            ),
          ],
        );
      }

      final history = await api.exerciseHistory(1);
      expect(history.map((s) => s.date.day), [3, 2, 1]);
    });
  });

  group('stats', () {
    test('an empty store reports empty stats', () async {
      final stats = await ApiClient().stats();
      expect(stats.totalWorkouts, 0);
      expect(stats.personalRecords, isEmpty);
    });

    test('personal records track the heaviest set', () async {
      final api = ApiClient();
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [
              WorkoutSetDraft(weight: 100, reps: 5),
              WorkoutSetDraft(weight: 185, reps: 3),
              WorkoutSetDraft(weight: 135, reps: 8),
            ],
          ),
        ],
      );

      final pr = (await api.stats()).personalRecords.single;
      expect(pr.heaviestWeight, 185);
      expect(pr.repsAtHeaviest, 3);
    });

    test('sets missing weight or reps do not count toward volume', () async {
      final api = ApiClient();
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [
              WorkoutSetDraft(weight: 100, reps: 5),
              WorkoutSetDraft(reps: 10),
              WorkoutSetDraft(weight: 50),
            ],
          ),
        ],
      );

      expect((await api.stats()).totalVolume, 500);
    });

    test('the week streak counts back from the current week', () async {
      final api = ApiClient();
      final now = DateTime.now();
      for (final weeksAgo in [0, 1, 2]) {
        await api.createWorkout(
          date: now.subtract(Duration(days: 7 * weeksAgo)),
          effortLevel: 5,
          exercises: [
            WorkoutExerciseDraft(
              exerciseId: 1,
              sets: [WorkoutSetDraft(weight: 100, reps: 5)],
            ),
          ],
        );
      }

      expect((await api.stats()).weekStreak, greaterThanOrEqualTo(3));
    });
  });

  group('muscle recovery', () {
    test('untrained groups are reported, not omitted', () async {
      final recovery = await ApiClient().muscleRecovery();
      expect(recovery, hasLength(MuscleGroups.all.length));
      expect(
        recovery.every((r) => r.status == RecoveryStatus.untrained),
        isTrue,
      );
    });

    test('a just-trained group reads as recovering', () async {
      final api = ApiClient();
      // Exercise 1 is Push-ups, muscle group Chest.
      await api.createWorkout(
        date: DateTime.now(),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [WorkoutSetDraft(weight: 0, reps: 20)],
          ),
        ],
      );

      final chest = (await api.muscleRecovery()).firstWhere(
        (r) => r.muscleGroup == MuscleGroups.chest,
      );
      expect(chest.status, RecoveryStatus.recovering);
      expect(chest.recoveryPercentage, lessThan(1.0));
    });

    test('a long-rested group reads as ready', () async {
      final api = ApiClient();
      await api.createWorkout(
        date: DateTime.now().subtract(const Duration(days: 30)),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [WorkoutSetDraft(weight: 0, reps: 20)],
          ),
        ],
      );

      final chest = (await api.muscleRecovery()).firstWhere(
        (r) => r.muscleGroup == MuscleGroups.chest,
      );
      expect(chest.status, RecoveryStatus.ready);
      expect(chest.recoveryPercentage, 1.0);
    });
  });

  group('templates', () {
    test('folder names must be unique', () async {
      final api = ApiClient();
      await api.createFolder(name: 'Push');
      expect(() => api.createFolder(name: 'push'), throwsStateError);
    });

    test('deleting a folder deletes its templates', () async {
      final api = ApiClient();
      final folder = await api.createFolder(name: 'Push');
      await api.createTemplate(
        folderId: folder.id,
        name: 'Bench day',
        exercises: [
          TemplateExercise(exerciseId: 1, order: 0, defaultSets: 3),
        ],
      );

      await api.deleteFolder(folder.id);
      expect(await api.listTemplates(), isEmpty);
    });

    test('template exercise rest is persisted and read back', () async {
      final api = ApiClient();
      final folder = await api.createFolder(name: 'Push');
      await api.createTemplate(
        folderId: folder.id,
        name: 'Bench day',
        exercises: [
          TemplateExercise(
            exerciseId: 1,
            order: 0,
            defaultSets: 3,
            restSeconds: 150,
          ),
        ],
      );

      final template = (await ApiClient().listTemplates()).single;
      expect(template.exercises.single.restSeconds, 150);
    });

    test('template exercise order is normalized to list position', () async {
      final api = ApiClient();
      final folder = await api.createFolder(name: 'Push');
      final template = await api.createTemplate(
        folderId: folder.id,
        name: 'Bench day',
        exercises: [
          TemplateExercise(exerciseId: 3, order: 99, defaultSets: 3),
          TemplateExercise(exerciseId: 1, order: 7, defaultSets: 3),
        ],
      );

      expect(template.exercises.map((e) => e.order), [0, 1]);
      expect(template.exercises.map((e) => e.exerciseId), [3, 1]);
    });
  });

  group('measurements', () {
    test('a kind gets its default unit', () async {
      final api = ApiClient();
      final m = await api.createMeasurement(
        date: DateTime(2026, 7, 1),
        kind: MeasurementKinds.bodyWeight,
        value: 180,
      );
      expect(m.unit, 'lb');
    });

    test('a series runs oldest first', () async {
      final api = ApiClient();
      for (final day in [3, 1, 2]) {
        await api.createMeasurement(
          date: DateTime(2026, 7, day),
          kind: MeasurementKinds.bodyWeight,
          value: 180.0 + day,
        );
      }

      final series = await api.measurementSeries(MeasurementKinds.bodyWeight);
      expect(series.map((p) => p.date.day), [1, 2, 3]);
    });

    test('a session stores every kind against one date', () async {
      final api = ApiClient();
      final created = await api.createMeasurements(
        date: DateTime(2026, 7, 4),
        entries: [
          MeasurementDraft(kind: MeasurementKinds.bodyWeight, value: 181),
          MeasurementDraft(kind: MeasurementKinds.waist, value: 33.5),
          MeasurementDraft(kind: MeasurementKinds.arm, value: 15.25),
        ],
      );

      expect(created, hasLength(3));
      expect(created.map((m) => m.id).toSet(), hasLength(3));
      expect(created.every((m) => m.date == DateTime(2026, 7, 4)), isTrue);
      // Units still come from the kind when the draft doesn't name one.
      expect(created.first.unit, 'lb');
      expect(created.last.unit, 'in');
      expect(await api.listMeasurements(), hasLength(3));
    });

    test('summaries cover only kinds with entries', () async {
      final api = ApiClient();
      await api.createMeasurements(
        date: DateTime(2026, 7, 1),
        entries: [
          MeasurementDraft(kind: MeasurementKinds.bodyWeight, value: 180),
          MeasurementDraft(kind: MeasurementKinds.waist, value: 34),
        ],
      );

      final summaries = await api.measurementSummaries();
      expect(summaries.map((s) => s.kind), [
        MeasurementKinds.bodyWeight,
        MeasurementKinds.waist,
      ]);
      expect(summaries.every((s) => s.entryCount == 1), isTrue);
      // One entry is no trend, so neither change is defined yet.
      expect(summaries.first.changeOverall, isNull);
      expect(summaries.first.changeLast, isNull);
    });

    test('a summary reports latest, overall change and last change', () async {
      final api = ApiClient();
      for (final entry in [(1, 180.0), (2, 178.0), (3, 175.0)]) {
        await api.createMeasurement(
          date: DateTime(2026, 7, entry.$1),
          kind: MeasurementKinds.bodyWeight,
          value: entry.$2,
        );
      }

      final summary = (await api.measurementSummaries()).single;
      expect(summary.latest, 175.0);
      expect(summary.latestDate, DateTime(2026, 7, 3));
      expect(summary.entryCount, 3);
      expect(summary.changeOverall, -5.0);
      expect(summary.changeLast, -3.0);
      expect(summary.series.map((p) => p.value), [180.0, 178.0, 175.0]);
    });

    test('summaries put unknown kinds after the standard ones', () async {
      final api = ApiClient();
      await api.createMeasurements(
        date: DateTime(2026, 7, 1),
        entries: [
          MeasurementDraft(kind: 'Forearm', value: 12),
          MeasurementDraft(kind: MeasurementKinds.chest, value: 42),
        ],
      );

      final summaries = await api.measurementSummaries();
      expect(summaries.map((s) => s.kind), [MeasurementKinds.chest, 'Forearm']);
    });

    test('a rolling average smooths within its window', () async {
      final points = [
        TimePoint(DateTime(2026, 7, 1), 180),
        TimePoint(DateTime(2026, 7, 2), 184),
        TimePoint(DateTime(2026, 7, 3), 176),
      ];

      final smoothed = ApiClient.rollingAverage(points);

      expect(smoothed, hasLength(3));
      // Each point averages everything within the preceding window, so the
      // first is itself and the series never runs ahead of the data.
      expect(smoothed[0].value, 180);
      expect(smoothed[1].value, 182);
      expect(smoothed[2].value, 180);
      expect(smoothed.map((p) => p.date), points.map((p) => p.date));
    });

    test('a rolling average drops readings outside the window', () async {
      final points = [
        TimePoint(DateTime(2026, 7, 1), 200),
        TimePoint(DateTime(2026, 7, 20), 180),
        TimePoint(DateTime(2026, 7, 21), 178),
      ];

      final smoothed = ApiClient.rollingAverage(points);

      // The July 1 reading is far outside the 7-day window by the 20th, so it
      // can't drag the average.
      expect(smoothed[1].value, 180);
      expect(smoothed[2].value, 179);
    });

    test('a rolling average needs two points', () async {
      expect(ApiClient.rollingAverage(const []), isEmpty);
      expect(
        ApiClient.rollingAverage([TimePoint(DateTime(2026, 7, 1), 180)]),
        isEmpty,
      );
    });
  });

  group('persistence', () {
    test('data survives a new client against the same file', () async {
      await ApiClient().createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 9,
        notes: 'heavy',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [WorkoutSetDraft(weight: 225, reps: 5)],
          ),
        ],
      );

      final reopened = await ApiClient().listWorkouts();
      expect(reopened.single.notes, 'heavy');
      expect(reopened.single.exercises.single.sets.single.weight, 225);
    });

    test('an unreadable file is quarantined, not discarded', () async {
      storeFile().writeAsStringSync('{ this is not json');

      final api = ApiClient();
      // Falls back to a fresh seeded store rather than throwing.
      expect(await api.listExercises(), hasLength(40));

      final quarantined = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt-'));
      expect(quarantined, hasLength(1));
      expect(quarantined.single.readAsStringSync(), '{ this is not json');
    });

    test('a file from a newer schema is quarantined, not mangled', () async {
      storeFile().writeAsStringSync(jsonEncode({'schema_version': 99}));

      await ApiClient().listExercises();

      expect(
        dir.listSync().whereType<File>().where(
          (f) => f.path.contains('.corrupt-'),
        ),
        hasLength(1),
      );
    });
  });

  group('export and import', () {
    test('an export round-trips through import', () async {
      final api = ApiClient();
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 6,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [WorkoutSetDraft(weight: 315, reps: 2)],
          ),
        ],
      );
      final exported = await api.exportJson();

      final fresh = ApiClient();
      await fresh.resetAll();
      expect(await fresh.listWorkouts(), isEmpty);

      await fresh.importJson(exported);
      final restored = await fresh.listWorkouts();
      expect(restored, hasLength(1));
      expect(restored.single.exercises.single.sets.single.weight, 315);
    });

    test('import rejects a file that is not a backup', () async {
      final api = ApiClient();
      await expectLater(
        api.importJson('{"hello": "world"}'),
        throwsA(isA<ImportException>()),
      );
      // The existing store is left intact.
      expect(await api.listExercises(), hasLength(40));
    });

    test('import copies the current file aside first', () async {
      final api = ApiClient();
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [WorkoutSetDraft(weight: 100, reps: 5)],
          ),
        ],
      );
      final exported = await api.exportJson();
      await api.importJson(exported);

      expect(
        dir.listSync().whereType<File>().where(
          (f) => f.path.contains('.pre-import-'),
        ),
        hasLength(1),
      );
    });
  });

  group('CSV', () {
    test('workouts export to CSV, one row per set', () async {
      final api = ApiClient();
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 7,
        templateName: 'Push',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [
              WorkoutSetDraft(weight: 135, reps: 8),
              WorkoutSetDraft(weight: 145, reps: 6),
            ],
          ),
        ],
      );

      final csv = await api.exportWorkoutsCsv();
      final lines = csv.trim().split('\n');
      expect(lines.first, startsWith('Date,Workout Name,Exercise Name'));
      expect(lines.length, 3); // header + two sets
      expect(lines[1], contains('Push'));
      expect(lines[1], contains('135'));
    });

    test('imports a Strong-style CSV, grouping sets into workouts', () async {
      final api = ApiClient();
      const csv =
          'Date,Workout Name,Exercise Name,Set Order,Weight,Reps,RPE\n'
          '2026-07-01 08:00:00,Push,Bench Press,1,135,8,8\n'
          '2026-07-01 08:00:00,Push,Bench Press,2,135,7,9\n'
          '2026-07-01 08:00:00,Push,Overhead Press,1,95,5,\n'
          '2026-07-03 08:00:00,Pull,Barbell Rows,1,155,8,\n';

      final result = await api.importWorkoutsCsv(csv, weightsInKg: false);
      expect(result.workouts, 2);
      expect(result.sets, 4);
      // "Bench Press" / "Overhead Press" — Overhead Press exists in the seed
      // library, Bench Press doesn't (it's "Barbell Bench Press"), so some are
      // created.
      expect(result.exercisesCreated, greaterThan(0));

      final workouts = await api.listWorkouts();
      expect(workouts, hasLength(2));
      final push = workouts.firstWhere((w) => w.templateName == 'Push');
      expect(push.exercises, hasLength(2));
      expect(push.exercises.first.sets, hasLength(2));
      // Average RPE 8.5 → rounds to effort 9.
      expect(push.effortLevel, 9);
    });

    test('Strong-style names map onto the seed library, no duplicates',
        () async {
      final api = ApiClient();
      final seedCount = (await api.listExercises()).length;

      // Strong's "Movement (Equipment)" against Forma's "Equipment Movement",
      // plus plural and bodyweight differences.
      const csv =
          'Date,Exercise Name,Weight,Reps\n'
          '2026-07-01,Bench Press (Barbell),135,5\n'
          '2026-07-01,Squat (Barbell),225,5\n'
          '2026-07-01,Pull Up (Bodyweight),0,10\n'
          '2026-07-01,Lat Pulldown (Cable),120,10\n'
          '2026-07-01,Deadlift (Barbell),315,3\n';

      final result = await api.importWorkoutsCsv(csv, weightsInKg: false);
      // All five resolve to existing seed exercises → none created.
      expect(result.exercisesCreated, 0);
      expect(await api.listExercises(), hasLength(seedCount));
    });

    test('equipment disambiguates variants that share a base', () async {
      final api = ApiClient();
      final byName = {
        for (final e in await api.listExercises()) e.name: e.id,
      };
      // Seed has both "Barbell Bench Press" and "Dumbbell Bench Press".
      const csv =
          'Date,Exercise Name,Weight,Reps\n'
          '2026-07-01,Bench Press (Dumbbell),50,10\n';

      await api.importWorkoutsCsv(csv, weightsInKg: false);
      final logged =
          (await api.listWorkouts()).single.exercises.single.exerciseId;
      expect(logged, byName['Dumbbell Bench Press']);
    });

    test('a genuinely unknown exercise is still created', () async {
      final api = ApiClient();
      const csv =
          'Date,Exercise Name,Weight,Reps\n'
          '2026-07-01,Zercher Squat (Barbell),185,5\n';

      final result = await api.importWorkoutsCsv(csv, weightsInKg: false);
      expect(result.exercisesCreated, 1);
    });

    test('kg weights convert to pounds on import', () async {
      final api = ApiClient();
      const csv =
          'Date,Workout Name,Exercise Name,Set Order,Weight,Reps\n'
          '2026-07-01,Legs,Squat,1,100,5\n';

      await api.importWorkoutsCsv(csv, weightsInKg: true);
      final set = (await api.listWorkouts()).single.exercises.single.sets.single;
      expect(set.weight, closeTo(220.5, 0.1)); // 100 kg → 220.5 lb
    });

    test('a "Weight (kg)" header forces kg regardless of the toggle', () async {
      final api = ApiClient();
      const csv =
          'Date,Exercise Name,Weight (kg),Reps\n'
          '2026-07-01,Deadlift,100,5\n';

      await api.importWorkoutsCsv(csv, weightsInKg: false);
      final set = (await api.listWorkouts()).single.exercises.single.sets.single;
      expect(set.weight, closeTo(220.5, 0.1));
    });

    test('a non-workout CSV is rejected with a clear message', () async {
      final api = ApiClient();
      await expectLater(
        api.importWorkoutsCsv('a,b,c\n1,2,3\n', weightsInKg: false),
        throwsA(isA<ImportException>()),
      );
    });

    test('an export round-trips back through import', () async {
      final api = ApiClient();
      await api.createWorkout(
        date: DateTime(2026, 7, 1),
        effortLevel: 5,
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 1,
            sets: [WorkoutSetDraft(weight: 100, reps: 5)],
          ),
        ],
      );
      final csv = await api.exportWorkoutsCsv();

      final fresh = ApiClient();
      await fresh.resetAll();
      final result = await fresh.importWorkoutsCsv(csv, weightsInKg: false);
      expect(result.workouts, 1);
      expect(result.sets, 1);
      expect((await fresh.listWorkouts()).single.exercises.single.sets.single.weight, 100);
    });
  });

  test('concurrent writes do not lose records', () async {
    final api = ApiClient();
    // Fire mutations without awaiting between them: the write queue must
    // serialize the read-modify-write cycles.
    await Future.wait([
      for (var i = 0; i < 20; i++) api.createExercise(name: 'Lift $i'),
    ]);

    final exercises = await api.listExercises();
    expect(exercises.where((e) => e.name.startsWith('Lift ')), hasLength(20));
    expect(exercises.map((e) => e.id).toSet(), hasLength(exercises.length));
  });
}
