import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/glass.dart';
import 'analytics_screen.dart';
import 'dashboard_screen.dart';
import 'exercise_library_screen.dart';
import 'measurements_screen.dart';
import 'settings_screen.dart';
import 'templates/folder_list_screen.dart';
import 'workout/log_workout_screen.dart';

const _tabs = <GlassTab>[
  GlassTab(icon: Icon(Icons.home_outlined), label: 'Home'),
  GlassTab(icon: Icon(Icons.fitness_center), label: 'Exercises'),
  GlassTab(icon: Icon(Icons.folder_outlined), label: 'Templates'),
  GlassTab(icon: Icon(Icons.insights), label: 'Progress'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = ['Forma', 'Exercises', 'Templates', 'Progress'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // The large title shares its row with the glass action buttons.
            LargeTitle(
              _titles[_index],
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_index == 3) ...[
                    GlassIconButton(
                      icon: const Icon(Icons.straighten),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MeasurementsScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  GlassIconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LogWorkoutScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassIconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: const [
                  DashboardScreen(),
                  ExerciseLibraryScreen(),
                  FolderListScreen(),
                  AnalyticsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: GlassTabBar.bottom(
        tabs: _tabs,
        selectedIndex: _index,
        onTabSelected: (i) => setState(() => _index = i),
        selectedIconColor: AppColors.primary,
        selectedLabelColor: AppColors.primary,
        unselectedIconColor: AppColors.inactiveNav,
        unselectedLabelColor: AppColors.inactiveNav,
      ),
    );
  }
}
