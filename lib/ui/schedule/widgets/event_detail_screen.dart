import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show ScreenSize;
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/event_detail_viewmodel.dart';
import 'event_style.dart';

/// Opens a team event's full details and RSVP over the current page: a
/// dialog on wide screens, a sheet that slides up on phones.
Future<void> showEventDetails(
  BuildContext context, {
  required String teamId,
  required String eventId,
}) {
  Widget content(BuildContext _) => ViewModelHost(
    key: ValueKey('event-$teamId-$eventId'),
    create: (c) => EventDetailViewModel(
      teamId: teamId,
      eventId: eventId,
      eventRepository: c.read(),
      teamRepository: c.read(),
      authRepository: c.read(),
      tournamentRepository: c.read(),
    ),
    builder: (_, vm) => EventDetailScreen(viewModel: vm, popup: true),
  );
  if (ScreenSize.of(context).isMobile) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: content,
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: content(context),
      ),
    ),
  );
}

/// A team event: details, RSVP, reactions, poll and who's coming. A page of
/// its own (e.g. from a notification), or the body of [showEventDetails].
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.viewModel,
    this.popup = false,
  });

  final EventDetailViewModel viewModel;

  /// Shown over another page by [showEventDetails]: no app bar, and
  /// leaving closes the popup.
  final bool popup;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  EventDetailViewModel get vm => widget.viewModel;
  bool get popup => widget.popup;

  late final List<Command<void>> _commands = [
    vm.setRsvp,
    vm.toggleReaction,
    vm.vote,
    vm.deleteEvent,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    super.dispose();
  }

  void _onCommand() {
    if (vm.deleteEvent.completed) {
      vm.deleteEvent.clearResult();
      if (popup) {
        Navigator.pop(context);
      } else {
        context.canPop() ? context.pop() : context.go(Routes.team(vm.teamId));
      }
      return;
    }
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  Future<void> _delete(TeamEvent e) async {
    if (await confirmDialog(
      context,
      title: 'Delete "${e.title}"?',
      message: 'RSVPs, reactions and poll votes will be lost.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.deleteEvent.execute();
    }
  }

  /// Opens [route] as a page; from a popup, closes the popup first.
  void _open(String route) {
    if (popup) {
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.push(route);
    } else {
      context.push(route);
    }
  }

  List<Widget> _actions(TeamEvent e) => [
    if (vm.canEdit) ...[
      IconButton(
        tooltip: 'Edit',
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => _open(Routes.editEvent(vm.teamId, vm.eventId)),
      ),
      IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(e),
      ),
    ],
  ];

  List<Widget> _details(TeamEvent e) => [
    EventHeader(event: e),
    if (vm.tournament case final t?) ...[
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => _open(Routes.groupTournament(vm.teamId, t.id)),
        icon: const Icon(Icons.emoji_events_outlined),
        label: Text('View ${t.name}'),
      ),
    ] else if (vm.canSetUpTournament) ...[
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () =>
            _open(Routes.newGroupTournament(vm.teamId, eventId: vm.eventId)),
        icon: const Icon(Icons.emoji_events_outlined),
        label: const Text('Set up tournament'),
      ),
    ],
    const SizedBox(height: 20),
    _RsvpSection(viewModel: vm),
    const SizedBox(height: 16),
    _Reactions(viewModel: vm),
    if (e.poll != null) ...[
      const SizedBox(height: 20),
      _PollCard(viewModel: vm, poll: e.poll!),
    ],
    const SizedBox(height: 20),
    _Responses(viewModel: vm),
  ];

  /// The popup's frame: a title row with the actions and Close, then [body].
  Widget _popup(
    Widget body, {
    String title = '',
    List<Widget> actions = const [],
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...actions,
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      Flexible(child: body),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final e = vm.event;
        final Widget? missing = !vm.loaded
            ? const LoadingView()
            : e != null
            ? null
            : vm.error != null
            ? ErrorView(error: vm.error)
            : const EmptyView(
                icon: Icons.event_busy_outlined,
                title: 'Event not available',
                message: 'It may have been deleted.',
              );
        if (missing != null) {
          if (popup) return _popup(SizedBox(height: 240, child: missing));
          return Scaffold(
            appBar: AppBar(leading: backOr(context, Routes.team(vm.teamId))),
            body: missing,
          );
        }
        final list = ListView(
          shrinkWrap: popup,
          padding: popup
              ? const EdgeInsets.fromLTRB(20, 4, 20, 24)
              : const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: _details(e!),
        );
        if (popup) {
          return _popup(list, title: e.type.label, actions: _actions(e));
        }
        return Scaffold(
          appBar: AppBar(
            leading: backOr(context, Routes.team(vm.teamId)),
            title: Text(e.type.label),
            actions: _actions(e),
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: list,
            ),
          ),
        );
      },
    );
  }
}

/// Icon, title, time, location and notes of an event.
class EventHeader extends StatelessWidget {
  const EventHeader({super.key, required this.event});

  final TeamEvent event;

  Future<void> _openMap() => launchUrl(
    Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': event.location,
    }),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = event;
    final color = e.type.color(theme.colorScheme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              foregroundColor: color,
              child: Icon(e.type.icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(e.title, style: theme.textTheme.headlineSmall),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(DateFormat.yMMMMEEEEd().format(e.startsAt)),
          subtitle: Text(eventTimeRange(e)),
        ),
        if (e.location.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(e.location),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: _openMap,
          ),
        if (e.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(e.notes, style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

class _RsvpSection extends StatelessWidget {
  const _RsvpSection({required this.viewModel});

  final EventDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final mine = vm.myRsvp;
    final r = vm.responses;
    final type = vm.event?.type ?? EventType.other;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Are you in?', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<RsvpStatus>(
              segments: [
                for (final s in RsvpStatus.values)
                  ButtonSegment(
                    value: s,
                    label: Text(s.labelFor(type)),
                    icon: Icon(s.icon),
                  ),
              ],
              selected: {?mine},
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              onSelectionChanged: vm.setRsvp.running
                  ? null
                  : (s) => vm.setRsvp.execute(s.firstOrNull),
            ),
            const SizedBox(height: 12),
            Text(
              [
                for (final s in RsvpStatus.values)
                  '${r[s]!.length} ${s.labelFor(type).toLowerCase()}',
                '${vm.noResponse.length} no reply',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Reactions extends StatelessWidget {
  const _Reactions({required this.viewModel});

  final EventDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final tally = vm.reactions;
    final mine = vm.myReactions;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final r in Reaction.values)
          Tooltip(
            message: tally[r]?.join(', ') ?? 'React',
            child: FilterChip(
              showCheckmark: false,
              selected: mine.contains(r),
              label: Text(
                tally[r] == null ? r.emoji : '${r.emoji} ${tally[r]!.length}',
              ),
              onSelected: vm.canRespond
                  ? (_) => vm.toggleReaction.execute(r)
                  : null,
            ),
          ),
        if (!vm.canRespond)
          Text(
            'RSVP "Going" to react and vote.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({required this.viewModel, required this.poll});

  final EventDetailViewModel viewModel;
  final EventPoll poll;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tally = vm.pollTally;
    final total = vm.event?.voterCount ?? 0;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.poll_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    poll.question,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${poll.multiple ? 'Pick any' : 'Pick one'} · '
              '$total of ${vm.memberCount} voted',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final t in tally)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Tooltip(
                  message: t.voters.isEmpty ? 'No votes' : t.voters.join(', '),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: vm.vote.running || !vm.canRespond
                        ? null
                        : () => vm.vote.execute(t.option.id),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: t.mine
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: t.mine ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: total == 0
                                  ? 0
                                  : t.voters.length / total,
                              child: ColoredBox(
                                color: scheme.primary.withValues(alpha: 0.14),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  t.mine
                                      ? (poll.multiple
                                            ? Icons.check_box
                                            : Icons.radio_button_checked)
                                      : (poll.multiple
                                            ? Icons.check_box_outline_blank
                                            : Icons.radio_button_unchecked),
                                  size: 20,
                                  color: t.mine ? scheme.primary : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(t.option.text)),
                                Text(
                                  '${t.voters.length}',
                                  style: theme.textTheme.labelLarge,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Responses extends StatelessWidget {
  const _Responses({required this.viewModel});

  final EventDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = viewModel.responses;
    final type = viewModel.event?.type ?? EventType.other;
    final groups = [
      for (final s in RsvpStatus.values)
        (s.labelFor(type), s.icon, s.color(scheme), r[s]!),
      ('No reply', Icons.hourglass_empty, scheme.outline, viewModel.noResponse),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Responses', style: Theme.of(context).textTheme.titleMedium),
        for (final (label, icon, color, names) in groups)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: Icon(icon, color: color),
            title: Text('$label (${names.length})'),
            initiallyExpanded: label == RsvpStatus.going.labelFor(type),
            expandedAlignment: Alignment.centerLeft,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              if (names.isEmpty)
                const Text('Nobody yet.')
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final n in names) Chip(label: Text(n))],
                ),
            ],
          ),
      ],
    );
  }
}
