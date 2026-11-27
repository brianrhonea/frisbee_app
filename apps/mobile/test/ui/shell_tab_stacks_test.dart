// N3 (rest): tapping the active tab returns it to its first page, and each
// tab keeps its own back stack, on the real router over fakes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:go_router/go_router.dart';

import '../testing/app_harness.dart';

Future<void> _tab(WidgetTester t, String label) async {
  await t.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await t.pumpAndSettle();
}

Future<void> _openTeam(WidgetTester t) async {
  await _tab(t, 'Teams');
  await t.tap(find.text('Northside Flyers').first);
  await t.pumpAndSettle();
  expect(find.byType(TeamHomeScreen), findsOneWidget);
}

void main() {
  testWidgets('N3: the active tab again returns the Teams tab to its list', (
    t,
  ) async {
    await pumpFullApp(t);
    await _openTeam(t);
    await _tab(t, 'Teams');
    expect(find.byType(TeamsScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);
  });

  testWidgets('N3: the active tab again leaves a team section for the list', (
    t,
  ) async {
    await pumpFullApp(t);
    GoRouter.of(
      t.element(find.byType(NavigationBar)),
    ).go('/teams/t1?section=roster');
    await t.pumpAndSettle();
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    await _tab(t, 'Teams');
    expect(find.byType(TeamsScreen), findsOneWidget);
  });

  testWidgets('N3: a tab left on a deeper page comes back to it', (t) async {
    await pumpFullApp(t);
    await _openTeam(t);
    await _tab(t, 'Discover');
    expect(find.byType(ExploreScreen), findsOneWidget);
    await _tab(t, 'Teams');
    expect(find.byType(TeamHomeScreen), findsOneWidget);
  });

  testWidgets('N3: each tab keeps its own stack', (t) async {
    await pumpFullApp(t);
    final router = GoRouter.of(t.element(find.byType(NavigationBar)));
    // Discover goes one page deeper (a player), Teams one page deeper
    // (a team).
    await _tab(t, 'Discover');
    router.go('/players/u2');
    await t.pumpAndSettle();
    expect(find.byType(PlayerProfileScreen), findsOneWidget);
    await _openTeam(t);

    // Back in Discover: still on the player, not the team.
    await _tab(t, 'Discover');
    expect(find.byType(PlayerProfileScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);

    // And in Teams: still on the team.
    await _tab(t, 'Teams');
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    expect(find.byType(PlayerProfileScreen), findsNothing);

    // Tapping Teams again resets only Teams: Discover keeps its player.
    await _tab(t, 'Teams');
    expect(find.byType(TeamsScreen), findsOneWidget);
    await _tab(t, 'Discover');
    expect(find.byType(PlayerProfileScreen), findsOneWidget);
  });
}
