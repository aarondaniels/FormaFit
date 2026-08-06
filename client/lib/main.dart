import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The rest-timer chime is an alert, not media: it should be heard over the
  // silent switch (the default) but must not stop whatever the user is
  // listening to. `gain` — the default focus — claims to be the sole audio
  // source and interrupts their music every time rest ends; ducking lowers it
  // for the chime instead.
  await AudioPlayer.global.setAudioContext(
    AudioContextConfig(focus: AudioContextConfigFocus.duckOthers).build(),
  );
  await LiquidGlassWidgets.initialize();
  runApp(
    LiquidGlassWidgets.wrap(
      // adaptiveQuality: benchmarks the device and steps shader quality down
      // automatically on weaker hardware instead of janking.
      adaptiveQuality: true,
      child: const ProviderScope(child: FormaApp()),
    ),
  );
}

class FormaApp extends StatelessWidget {
  const FormaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Forma',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const HomeScreen(),
    );
  }
}
