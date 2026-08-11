/// The starter library seeded into an empty store on first launch.
///
/// Ids are fixed and low so they stay stable across installs and never collide
/// with user-created records, which start above [seedIdCeiling].
library;

import '../models.dart';

/// Ids at or below this belong to the seeded library. The store's id counters
/// start above it so user records can never reuse a seed id.
const int seedIdCeiling = 1000;

const List<Map<String, Object?>> _equipmentSeed = [
  {
    'id': 1,
    'name': 'Bodyweight',
    'description': 'Exercises that use only your body weight for resistance',
    'icon': 'body',
    'category': 'strength',
  },
  {
    'id': 2,
    'name': 'Dumbbell',
    'description': 'Free weights that can be used for various exercises',
    'icon': 'dumbbell',
    'category': 'strength',
  },
  {
    'id': 3,
    'name': 'Barbell',
    'description': 'Long bar with weights for compound movements',
    'icon': 'barbell',
    'category': 'strength',
  },
  {
    'id': 4,
    'name': 'Cable Machine',
    'description': 'Machine that provides constant tension through cables',
    'icon': 'cable',
    'category': 'strength',
  },
  {
    'id': 5,
    'name': 'Machine',
    'description': 'Weight machines that guide movement patterns',
    'icon': 'machine',
    'category': 'strength',
  },
  {
    'id': 6,
    'name': 'Resistance Band',
    'description': 'Elastic bands that provide variable resistance',
    'icon': 'band',
    'category': 'strength',
  },
];

const List<Map<String, Object?>> _exerciseSeed = [
  {
    'id': 1,
    'name': 'Push-ups',
    'muscle_group': 'Chest',
    'description':
        'Classic bodyweight chest exercise that targets pectorals, triceps, and shoulders',
    'equipment_type_id': 1,
    'instructions':
        'Start in plank position, lower body until chest nearly touches ground, then push back up',
    'is_bodyweight': true,
  },
  {
    'id': 2,
    'name': 'Dumbbell Bench Press',
    'muscle_group': 'Chest',
    'description':
        'Compound chest exercise using dumbbells for balanced muscle development',
    'equipment_type_id': 2,
    'instructions':
        'Lie on bench, hold dumbbells at chest level, press up and together, then lower with control',
  },
  {
    'id': 3,
    'name': 'Barbell Bench Press',
    'muscle_group': 'Chest',
    'description':
        'Fundamental compound movement for building chest strength and size',
    'equipment_type_id': 3,
    'instructions':
        'Lie on bench, grip barbell slightly wider than shoulders, lower to chest, press up',
  },
  {
    'id': 4,
    'name': 'Incline Dumbbell Press',
    'muscle_group': 'Chest',
    'description': 'Upper chest focused exercise using inclined bench',
    'equipment_type_id': 2,
    'instructions':
        'Set bench to 30-45 degree incline, perform dumbbell press focusing on upper chest',
  },
  {
    'id': 5,
    'name': 'Cable Flyes',
    'muscle_group': 'Chest',
    'description':
        'Isolation exercise for chest using cable machine for constant tension',
    'equipment_type_id': 4,
    'instructions':
        'Stand between cable pulleys, bring hands together in front of chest with slight bend',
  },
  {
    'id': 6,
    'name': 'Pull-ups',
    'muscle_group': 'Back',
    'description': 'Compound back exercise that builds upper body strength',
    'equipment_type_id': 1,
    'instructions':
        'Hang from pull-up bar, pull body up until chin over bar, lower with control',
  },
  {
    'id': 7,
    'name': 'Barbell Rows',
    'muscle_group': 'Back',
    'description':
        'Compound back exercise targeting lats, rhomboids, and rear deltoids',
    'equipment_type_id': 3,
    'instructions':
        'Bend at hips, grip barbell, pull elbows back to bring bar to lower chest',
  },
  {
    'id': 8,
    'name': 'Dumbbell Rows',
    'muscle_group': 'Back',
    'description':
        'Unilateral back exercise that helps identify and correct muscle imbalances',
    'equipment_type_id': 2,
    'instructions':
        'Place knee on bench, pull dumbbell up to hip, focus on squeezing shoulder blades',
  },
  {
    'id': 9,
    'name': 'Lat Pulldowns',
    'muscle_group': 'Back',
    'description':
        'Machine-based exercise that mimics pull-ups for building lat width',
    'equipment_type_id': 5,
    'instructions':
        'Sit at lat pulldown machine, pull bar down to upper chest, control the return',
  },
  {
    'id': 10,
    'name': 'Face Pulls',
    'muscle_group': 'Back',
    'description': 'Rear deltoid and upper back exercise using cable machine',
    'equipment_type_id': 4,
    'instructions':
        'Pull cable to face level, focus on squeezing shoulder blades and rear deltoids',
  },
  {
    'id': 11,
    'name': 'Overhead Press',
    'muscle_group': 'Shoulders',
    'description':
        'Compound shoulder exercise that builds overall shoulder strength and stability',
    'equipment_type_id': 3,
    'instructions':
        'Stand with barbell at shoulder level, press overhead while maintaining core stability',
  },
  {
    'id': 12,
    'name': 'Dumbbell Shoulder Press',
    'muscle_group': 'Shoulders',
    'description':
        'Unilateral shoulder press that helps identify and correct imbalances',
    'equipment_type_id': 2,
    'instructions':
        'Sit or stand with dumbbells at shoulder level, press overhead with control',
  },
  {
    'id': 13,
    'name': 'Lateral Raises',
    'muscle_group': 'Shoulders',
    'description':
        'Isolation exercise targeting the lateral deltoids for shoulder width',
    'equipment_type_id': 2,
    'instructions':
        'Stand with dumbbells at sides, raise arms to shoulder level, control the descent',
  },
  {
    'id': 14,
    'name': 'Front Raises',
    'muscle_group': 'Shoulders',
    'description': 'Isolation exercise for anterior deltoids',
    'equipment_type_id': 2,
    'instructions':
        'Stand with dumbbells in front, raise arms to shoulder level, control the descent',
  },
  {
    'id': 15,
    'name': 'Reverse Flyes',
    'muscle_group': 'Shoulders',
    'description': 'Rear deltoid exercise using dumbbells or cables',
    'equipment_type_id': 2,
    'instructions':
        'Bend forward, raise arms to sides focusing on rear deltoids',
  },
  {
    'id': 16,
    'name': 'Bicep Curls',
    'muscle_group': 'Arms',
    'description': 'Classic bicep isolation exercise using dumbbells',
    'equipment_type_id': 2,
    'instructions':
        'Stand with dumbbells at sides, curl weights up to shoulders, control the descent',
  },
  {
    'id': 17,
    'name': 'Tricep Dips',
    'muscle_group': 'Arms',
    'description':
        'Compound tricep exercise using bodyweight or assisted machine',
    'equipment_type_id': 1,
    'instructions':
        'Support body on parallel bars, lower until upper arms are parallel to ground, press up',
  },
  {
    'id': 18,
    'name': 'Hammer Curls',
    'muscle_group': 'Arms',
    'description': 'Bicep and forearm exercise using neutral grip',
    'equipment_type_id': 2,
    'instructions':
        'Hold dumbbells with palms facing each other, curl up to shoulders',
  },
  {
    'id': 19,
    'name': 'Tricep Pushdowns',
    'muscle_group': 'Arms',
    'description': 'Cable-based tricep isolation exercise',
    'equipment_type_id': 4,
    'instructions':
        'Stand at cable machine, push bar down while keeping elbows at sides',
  },
  {
    'id': 20,
    'name': 'Preacher Curls',
    'muscle_group': 'Arms',
    'description': 'Isolated bicep exercise using preacher bench',
    'equipment_type_id': 2,
    'instructions':
        'Sit at preacher bench, curl dumbbell up with controlled movement',
  },
  {
    'id': 21,
    'name': 'Squats',
    'muscle_group': 'Legs',
    'description':
        'Fundamental compound leg exercise for overall lower body strength',
    'equipment_type_id': 1,
    'instructions':
        'Stand with feet shoulder-width apart, lower body as if sitting back, keep chest up',
  },
  {
    'id': 22,
    'name': 'Barbell Squats',
    'muscle_group': 'Legs',
    'description':
        'Heavy compound leg exercise for building strength and muscle',
    'equipment_type_id': 3,
    'instructions':
        'Rest barbell on upper back, squat down keeping chest up and knees in line with toes',
  },
  {
    'id': 23,
    'name': 'Deadlifts',
    'muscle_group': 'Legs',
    'description': 'Compound posterior chain exercise for overall strength',
    'equipment_type_id': 3,
    'instructions':
        'Stand over barbell, grip bar, lift by extending hips and knees, keep back straight',
  },
  {
    'id': 24,
    'name': 'Lunges',
    'muscle_group': 'Legs',
    'description': 'Unilateral leg exercise for balance and coordination',
    'equipment_type_id': 1,
    'instructions':
        'Step forward, lower back knee toward ground, push back to starting position',
  },
  {
    'id': 25,
    'name': 'Leg Press',
    'muscle_group': 'Legs',
    'description': 'Machine-based compound leg exercise',
    'equipment_type_id': 5,
    'instructions':
        'Sit in leg press machine, press weight away from body, control the return',
  },
  {
    'id': 26,
    'name': 'Plank',
    'muscle_group': 'Core',
    'description':
        'Isometric core exercise for building stability and endurance',
    'equipment_type_id': 1,
    'instructions':
        'Hold body in straight line from head to heels, engage core muscles',
    'is_bodyweight': true,
  },
  {
    'id': 27,
    'name': 'Crunches',
    'muscle_group': 'Core',
    'description': 'Basic abdominal exercise targeting rectus abdominis',
    'equipment_type_id': 1,
    'instructions':
        'Lie on back, lift shoulders off ground, contract abs, control the descent',
    'is_bodyweight': true,
  },
  {
    'id': 28,
    'name': 'Russian Twists',
    'muscle_group': 'Core',
    'description': 'Rotational core exercise for obliques',
    'equipment_type_id': 1,
    'instructions':
        'Sit with knees bent, lean back slightly, twist torso from side to side',
  },
  {
    'id': 29,
    'name': 'Mountain Climbers',
    'muscle_group': 'Core',
    'description': 'Dynamic core exercise that also provides cardio benefits',
    'equipment_type_id': 1,
    'instructions':
        'Start in plank position, alternate bringing knees to chest in running motion',
    'is_bodyweight': true,
  },
  {
    'id': 30,
    'name': 'Bicycle Crunches',
    'muscle_group': 'Core',
    'description': 'Advanced abdominal exercise combining crunch and rotation',
    'equipment_type_id': 1,
    'instructions':
        'Lie on back, lift shoulders, bring opposite elbow to opposite knee in cycling motion',
    'is_bodyweight': true,
  },
  {
    'id': 31,
    'name': 'Glute Bridges',
    'muscle_group': 'Glutes',
    'description': 'Isolation exercise for glute activation and strength',
    'equipment_type_id': 1,
    'instructions':
        'Lie on back, bend knees, lift hips while squeezing glutes, hold briefly',
    'is_bodyweight': true,
  },
  {
    'id': 32,
    'name': 'Hip Thrusts',
    'muscle_group': 'Glutes',
    'description': 'Advanced glute exercise for building strength and size',
    'equipment_type_id': 3,
    'instructions':
        'Rest upper back on bench, place barbell on hips, thrust hips up while squeezing glutes',
  },
  {
    'id': 33,
    'name': 'Donkey Kicks',
    'muscle_group': 'Glutes',
    'description': 'Bodyweight glute exercise that can be done anywhere',
    'equipment_type_id': 1,
    'instructions':
        'Start on hands and knees, kick one leg back and up, focus on glute contraction',
    'is_bodyweight': true,
  },
  {
    'id': 34,
    'name': 'Fire Hydrants',
    'muscle_group': 'Glutes',
    'description': 'Lateral glute exercise for hip abduction',
    'equipment_type_id': 1,
    'instructions':
        'Start on hands and knees, lift one leg to side while keeping knee bent',
    'is_bodyweight': true,
  },
  {
    'id': 35,
    'name': 'Cable Kickbacks',
    'muscle_group': 'Glutes',
    'description': 'Cable-based glute isolation exercise',
    'equipment_type_id': 4,
    'instructions':
        'Attach ankle strap to low cable, kick leg back while keeping it straight',
  },
  {
    'id': 36,
    'name': 'Standing Calf Raises',
    'muscle_group': 'Calves',
    'description':
        'Basic calf exercise that can be done with or without weight',
    'equipment_type_id': 1,
    'instructions':
        'Stand on edge of step, raise heels up, lower below step level, repeat',
  },
  {
    'id': 37,
    'name': 'Seated Calf Raises',
    'muscle_group': 'Calves',
    'description': 'Calf exercise that targets the soleus muscle',
    'equipment_type_id': 2,
    'instructions':
        'Sit with dumbbell on knees, raise heels up, lower with control',
  },
  {
    'id': 38,
    'name': 'Machine Calf Raises',
    'muscle_group': 'Calves',
    'description': 'Machine-based calf exercise for consistent resistance',
    'equipment_type_id': 5,
    'instructions':
        'Sit in calf raise machine, adjust weight, raise heels up and down',
  },
  {
    'id': 39,
    'name': 'Jump Rope',
    'muscle_group': 'Calves',
    'description': 'Cardio exercise that also builds calf endurance',
    'equipment_type_id': 1,
    'instructions':
        'Jump rope while staying on balls of feet, vary speed and patterns',
    'is_bodyweight': true,
  },
  {
    'id': 40,
    'name': 'Resistance Band Calf Raises',
    'muscle_group': 'Calves',
    'description': 'Calf exercise using resistance bands for variable tension',
    'equipment_type_id': 6,
    'instructions':
        'Step on resistance band, hold ends, perform calf raises against band resistance',
  },
];

List<EquipmentType> defaultEquipmentTypes() => _equipmentSeed
    .map(
      (e) => EquipmentType(
        id: e['id'] as int,
        name: e['name'] as String,
        description: e['description'] as String?,
        icon: e['icon'] as String?,
        category: e['category'] as String?,
      ),
    )
    .toList();

List<Exercise> defaultExercises() => _exerciseSeed
    .map(
      (e) => Exercise(
        id: e['id'] as int,
        name: e['name'] as String,
        muscleGroup: e['muscle_group'] as String?,
        description: e['description'] as String?,
        equipmentTypeId: e['equipment_type_id'] as int?,
        instructions: e['instructions'] as String?,
        isDefault: true,
        // Seeded only where a load is never really used. Pull-ups, dips,
        // squats, lunges and calf raises all share the "Bodyweight" equipment
        // type but take a belt or a dumbbell, and hiding their weight field
        // would make a loaded set impossible to log — a far more confusing
        // failure than an empty weight box someone can switch off in the
        // exercise editor. When in doubt, this stays false.
        isBodyweight: e['is_bodyweight'] as bool? ?? false,
      ),
    )
    .toList();
