import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/team/view_as_team_repository.dart';

import 'brand.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

// Profile opens from the avatar on Home, keeping the bar at five tabs.
const _destinations = [
  _Destination('Home', Icons.home_outlined, Icons.home),
  _Destination('Teams', Icons.groups_outlined, Icons.groups),
  _Destination('Schedule', Icons.calendar_month_outlined, Icons.calendar_month),
  _Destination('Events', Icons.emoji_events_outlined, Icons.emoji_events),
  _Destination('Rankings', Icons.leaderboard_outlined, Icons.leaderboard),
];

/// App shell: bottom navigation bar on narrow screens, navigation rail on
/// wide ones (tablet, desktop).
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const wideBreakpoint = 720.0;

  void _onSelect(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final viewAs = context.watch<ViewAsRole?>();
    final viewingAs = viewAs == null || viewAs.role == null
        ? null
        : _ViewingAsBar(viewAs: viewAs);
    if (!wide) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?viewingAs,
            NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onSelect,
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onSelect,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: UltiUpLogo(size: 36),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Expanded(child: navigationShell),
                ?viewingAs,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reminder that the developer "view as role" option is on.
class _ViewingAsBar extends StatelessWidget {
  const _ViewingAsBar({required this.viewAs});

  final ViewAsRole viewAs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 18,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Viewing as ${viewAs.role?.label}',
                style: TextStyle(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => viewAs.role = null,
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
