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
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(_titles[_index]),
        actions: [
          if (_index == 3)
            GlassIconButton(
              icon: const Icon(Icons.straighten),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MeasurementsScreen(),
                ),
              ),
            ),
          GlassIconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          ExerciseLibraryScreen(),
          FolderListScreen(),
          AnalyticsScreen(),
        ],
      ),
      floatingActionButton: Padding(
        // Lift the button clear of the floating tab bar.
        padding: EdgeInsets.only(bottom: glassBottomInset(context) - 56),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const LogWorkoutScreen()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Log workout'),
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
