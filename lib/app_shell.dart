import 'package:flutter/material.dart';
import 'package:ultimatefrisbeeapp/features/library/library_screen.dart';
import 'package:ultimatefrisbeeapp/features/practice/practice_screen.dart';
import 'package:ultimatefrisbeeapp/features/progress/progress_screen.dart';
import 'package:ultimatefrisbeeapp/features/settings/settings_screen.dart';
import 'package:ultimatefrisbeeapp/features/team/team_screen.dart';


class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  final screens = const [
    LibraryScreen(),
    PracticeScreen(),
    TeamScreen(),
    ProgressScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.event_note), label: 'Practice'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Team'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Progress'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
