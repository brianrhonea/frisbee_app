import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_shell.dart';
import 'data/hive_boxes.dart';
import 'data/seed_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  await Hive.openBox(HiveBoxes.drills);
  await Hive.openBox(HiveBoxes.plans);
  await Hive.openBox(HiveBoxes.sessions);

  // Seed only once (if empty)
  await seedIfNeeded();

  runApp(const ProviderScope(child: UltiCoachApp()));
}

class UltiCoachApp extends StatelessWidget {
  const UltiCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UltiCoach',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B6CB0)),
      ),
      home: const AppShell(),
    );
  }
}
