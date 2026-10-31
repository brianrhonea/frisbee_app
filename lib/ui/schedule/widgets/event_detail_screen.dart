import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/event_detail_viewmodel.dart';
import 'event_style.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.viewModel});

  final EventDetailViewModel viewModel;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  EventDetailViewModel get vm => widget.viewModel;

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
      context.canPop() ? context.pop() : context.go(Routes.team(vm.teamId));
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final e = vm.event;
        if (!vm.loaded) {
          return Scaffold(
            appBar: AppBar(leading: backOr(context, Routes.team(vm.teamId))),
            body: const LoadingView(),
          );
        }
        if (e == null) {
          return Scaffold(
            appBar: AppBar(leading: backOr(context, Routes.team(vm.teamId))),
            body: vm.error != null
                ? ErrorView(error: vm.error)
                : const EmptyView(
                    icon: Icons.event_busy_outlined,
                    title: 'Event not available',
                    message: 'It may have been deleted.',
                  ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            leading: backOr(context, Routes.team(vm.teamId)),
            title: Text(e.type.label),
            actions: [
              if (vm.canEdit) ...[
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      context.push(Routes.editEvent(vm.teamId, vm.eventId)),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(e),
                ),
              ],
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  EventHeader(event: e),
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
                ],
              ),
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
                    label: Text(s.label),
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
                  '${r[s]!.length} ${s.label.toLowerCase()}',
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
    final groups = [
      for (final s in RsvpStatus.values)
        (s.label, s.icon, s.color(scheme), r[s]!),
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
            initiallyExpanded: label == RsvpStatus.going.label,
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
