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
