import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

 main()  {
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
      home:  Container(color: Colors.blue),
    );
  }
}
