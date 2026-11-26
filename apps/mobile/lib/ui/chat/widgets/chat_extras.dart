import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/chat.dart';
import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../../schedule/widgets/rsvp_widgets.dart';
import '../view_models/chat_event_card_viewmodel.dart';
import '../view_models/chat_room_viewmodel.dart';

// Pins and event cards in team rooms (redesign F2, F3).

/// "When · where" for an event card or picker row.
String _when(TeamEvent e) => [
  DateFormat.MMMEd().add_jm().format(e.startsAt),
  if (e.location.trim().isNotEmpty) e.location.trim(),
].join(' · ');

/// The room has [chatPinsMax] pins: pick one to take down so [message]
/// can be pinned instead.
Future<void> showReplacePinSheet(
  BuildContext context,
  ChatRoomViewModel vm,
  ChatMessage message,
) async {
  final unpin = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _PinList(
      title: 'Unpin one to pin this',
      subtitle: 'A room holds $chatPinsMax pinned messages.',
      pins: vm.pins,
      onTap: (m) => Navigator.pop(context, m.id),
    ),
  );
  if (unpin != null) vm.replacePin.execute((message, unpin));
}

class _PinList extends StatelessWidget {
  const _PinList({
    required this.title,
    required this.pins,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final List<ChatMessage> pins;
  final ValueChanged<ChatMessage>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle case final s?)
                    Text(s, style: TextStyle(fontSize: 13, color: c.muted)),
                ],
              ),
            ),
            if (pins.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpace.xl),
                child: Text('Nothing is pinned.', textAlign: TextAlign.center),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: pins.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final m = pins[i];
                    final name = m.authorName.isEmpty ? 'Member' : m.authorName;
                    final sent = m.createdAt;
                    return Material(
                      color: c.card,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: c.border),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        onTap: onTap == null ? null : () => onTap!(m),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      [
                                        name,
                                        if (sent != null)
                                          DateFormat.MMMEd().format(sent),
                                      ].join(' · '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: c.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    // The whole text: opening the message
                                    // in a paged thread isn't cheap.
                                    SelectableText(
                                      m.text.isNotEmpty ? m.text : m.preview,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.45,
                                        color: c.ink2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A shared team event, as a card: date tile, title, time and place, the
/// viewer's answer and the Going count, and Going / Maybe / Can't go.
/// Says "Event no longer available" when it's deleted or not theirs to see.
class ChatEventCard extends StatelessWidget {
  const ChatEventCard({super.key, required this.teamId, required this.ref});

  final String teamId;
  final ChatEventRef ref;

  @override
  Widget build(BuildContext context) => ViewModelHost(
    key: ValueKey('event-card-$teamId-${ref.id}'),
    create: (c) => ChatEventCardViewModel(
      teamId: teamId,
      eventId: ref.id,
      eventRepository: c.read(),
      authRepository: c.read(),
    ),
    builder: (context, vm) => ListenableBuilder(
      listenable: Listenable.merge([vm, vm.setRsvp]),
      builder: (context, _) => _EventCardBody(viewModel: vm),
    ),
  );
}

class _EventCardBody extends StatelessWidget {
  const _EventCardBody({required this.viewModel});

  final ChatEventCardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final e = vm.event;
    final decoration = BoxDecoration(
      color: c.card,
      border: Border.all(color: c.border),
      borderRadius: BorderRadius.circular(AppRadius.card),
    );
    if (e == null) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: decoration,
        child: Row(
          children: [
            Icon(Icons.event_busy_outlined, size: 20, color: c.muted),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                vm.unavailable ? 'Event no longer available' : 'Loading event…',
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
            ),
          ],
        ),
      );
    }
    final going = vm.goingCount;
    final maybe = vm.maybeCount;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => context.push(Routes.event(vm.teamId, e.id)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DateBadge(date: e.startsAt, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: c.team,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  e.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: c.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            _when(e),
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                          Text(
                            [
                              '$going going',
                              if (maybe > 0) '$maybe maybe',
                            ].join(' · '),
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    if (vm.mine != null)
                      RsvpStatusPill(status: vm.mine, type: e.type),
                  ],
                ),
                if (!vm.isOver) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (vm.needsAnswer)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: NeedsYouPill('RSVP needed'),
                        ),
                      for (final s in RsvpStatus.values)
                        _RsvpButton(
                          label: s.label,
                          selected: vm.mine == s,
                          // Amber only for the one thing to do.
                          primary: vm.needsAnswer && s == RsvpStatus.going,
                          onPressed: vm.setRsvp.running
                              ? null
                              : () => vm.answer(s),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RsvpButton extends StatelessWidget {
  const _RsvpButton({
    required this.label,
    required this.selected,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool primary;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
    if (primary) {
      return FilledButton(
        style: style.merge(
          FilledButton.styleFrom(
            backgroundColor: c.highlight,
            foregroundColor: c.onHighlight,
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
    }
    if (selected) {
      return FilledButton(
        style: style.merge(
          FilledButton.styleFrom(
            backgroundColor: c.accentSoft,
            foregroundColor: c.accentInk,
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return OutlinedButton(
      style: style.merge(
        OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.border2),
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// "Share an event": the team's upcoming events; picking one posts it.
Future<void> showShareEventSheet(
  BuildContext context,
  ChatRoomViewModel vm,
) async {
  final team = vm.team;
  if (team == null) return;
  final id = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => ViewModelHost(
      create: (c) =>
          ChatEventPickerViewModel(team: team, eventRepository: c.read()),
      builder: (context, picker) => ListenableBuilder(
        listenable: picker,
        builder: (context, _) => _EventPicker(viewModel: picker),
      ),
    ),
  );
  if (id != null) vm.shareEvent.execute(id);
}

class _EventPicker extends StatelessWidget {
  const _EventPicker({required this.viewModel});

  final ChatEventPickerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final events = vm.events;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Share an event',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!vm.loaded)
              const Padding(
                padding: EdgeInsets.all(AppSpace.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (vm.error != null)
              ErrorView(error: vm.error)
            else if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpace.xl),
                child: Text(
                  vm.team.isOrganization
                      ? 'No upcoming events for everyone.'
                      : 'No upcoming events.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in events)
                      ListTile(
                        leading: DateBadge(date: e.startsAt),
                        title: Text(e.title),
                        subtitle: Text(_when(e)),
                        onTap: () => Navigator.pop(context, e.id),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
