import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../core/ui/layout.dart';

/// The Events tab's two views: the user's own schedule, and tournaments and
/// leagues anyone can find.
enum EventsView {
  schedule('My schedule', Routes.schedule),
  find('Find events', Routes.findEvents);

  const EventsView(this.label, this.route);
  final String label;
  final String route;

  /// The view `?view=` names; the schedule by default.
  static EventsView fromQuery(String? view) => view == 'find' ? find : schedule;
}

/// The tabs under the Events title, switching between [EventsView]s.
class EventsTabs extends StatelessWidget implements PreferredSizeWidget {
  const EventsTabs({super.key, required this.selected});

  final EventsView selected;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: UnderlineTabs(
      labels: [for (final v in EventsView.values) v.label],
      selected: selected.index,
      onSelect: (i) => context.go(EventsView.values[i].route),
    ),
  );
}
