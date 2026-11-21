import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';

/// Opens [location], a Teams-tab page (`/teams/...`), over the page
/// showing.
///
/// Inside the tabs that's a plain push. From a full-screen page outside
/// them (a tournament, a meeting, or a team page over one of those),
/// pushing a tab's page would stack a second copy of the tabs under it,
/// which leaves the tab bar stuck (the Teams tab kept opening Discover).
/// So there a team's page slides in as its [Routes.teamOver] copy, and
/// deeper team pages (roles, plays…) switch to the Teams tab instead.
void pushTeamRoute(BuildContext context, String location) {
  if (StatefulNavigationShell.maybeOf(context) != null) {
    context.push(location);
    return;
  }
  final uri = Uri.parse(location);
  final segments = uri.pathSegments;
  final teamPage = segments.length == 2 && '/${segments.first}' == Routes.teams;
  if (teamPage && segments[1] != 'new' && segments[1] != 'search') {
    context.push(Routes.asTeamOver(location));
  } else {
    context.go(location);
  }
}
