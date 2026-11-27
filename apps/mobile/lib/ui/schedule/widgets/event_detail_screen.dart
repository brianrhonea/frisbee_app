import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../calendar/widgets/add_to_calendar.dart';
import '../../../data/repositories/video/video_repository.dart';
import '../../../domain/models/team_event.dart';
import '../../core/ui/directions_sheet.dart';
import 'schedule_widgets.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/scoreboard.dart' show NeedsYouPill, SectionHeader;
import '../../core/ui/error_message.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart' show DateBadge, ScreenSize, SectionCard;
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/event_detail_viewmodel.dart';
import 'event_style.dart';
import 'rsvp_widgets.dart';

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
      videoRepository: readOptional<VideoRepository>(c),
    ),
    builder: (_, vm) => EventDetailScreen(viewModel: vm, popup: true),
  );
  if (ScreenSize.of(context).isMobile) {
    return showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AppMotion.sheetStyle(context),
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
    animationStyle: AppMotion.dialogStyle(context),
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
    vm.saveNote,
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
    if (e.series != null) {
      // A repeating event: this one, or it and every later one.
      final scope = await askSeriesScope(
        context,
        title: 'Delete "${e.title}"?',
        action: 'Delete',
      );
      if (scope != null) vm.deleteEvent.execute(scope);
      return;
    }
    if (await confirmDialog(
      context,
      title: 'Delete "${e.title}"?',
      message: 'RSVPs, reactions and poll votes will be lost.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.deleteEvent.execute(SeriesScope.one);
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
    EventHeader(
      event: e,
      owner: vm.teamName,
      calendarButton: AddToCalendarButton(
        event: e,
        uid: 'team-${vm.teamId}-${e.id}@stall10.app',
      ),
    ),
    if (e.tournamentId case final id?) ...[
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => _open(Routes.tournament(id)),
        icon: const Icon(Icons.emoji_events_outlined),
        label: const Text('Open tournament page'),
      ),
    ] else if (vm.tournament case final t?) ...[
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
    const SizedBox(height: 12),
    _RsvpSection(viewModel: vm),
    const SizedBox(height: 12),
    _Reactions(viewModel: vm),
    if (e.poll != null) ...[
      const SizedBox(height: 12),
      _PollCard(viewModel: vm, poll: e.poll!),
    ],
    const SizedBox(height: 12),
    _Responses(viewModel: vm),
    if (e.notes.isNotEmpty) ...[
      const SizedBox(height: 12),
      EventNotes(notes: e.notes),
    ],
    if (vm.videos.isNotEmpty) ...[
      const SizedBox(height: 12),
      SectionCard(
        title: 'Videos',
        icon: Icons.smart_display_outlined,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          children: [
            for (final v in vm.videos)
              ListTile(
                key: ValueKey('event-video-${v.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.play_circle_outline),
                title: Text(
                  v.title.isEmpty ? 'Video' : v.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(Routes.video(vm.teamId, v.id)),
              ),
          ],
        ),
      ),
    ],
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
        padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.of(context).ink,
                ),
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
            ? const LoadingState()
            : e != null
            ? null
            : vm.error != null
            ? ErrorState(error: vm.error)
            : const EmptyState(
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
              ? const EdgeInsets.fromLTRB(16, 4, 16, 24)
              : const EdgeInsets.fromLTRB(16, 14, 16, 32),
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

/// An event's summary: a cover band with its date badge on the edge
/// (`CoverHeader`), the title with whose schedule it's on and its type,
/// then the day and time, the location (tap for directions) and
/// [calendarButton]. Notes go in [EventNotes].
class EventHeader extends StatelessWidget {
  const EventHeader({
    super.key,
    required this.event,
    this.owner,
    this.personal = false,
    this.calendarButton,
  });

  final TeamEvent event;

  /// Whose schedule it's on, e.g. the team's name, before the type.
  final String? owner;

  /// A personal event (kept for callers; the cover has no team colour).
  final bool personal;

  /// "Add to calendar", under the details.
  final Widget? calendarButton;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final e = event;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Events have no cover picture, so no empty band: the date badge
        // and title sit on the page.
        Row(
          children: [
            DateBadge(date: e.startsAt, size: 64),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, style: AppText.heading3.copyWith(color: c.ink)),
                  Text(
                    [?owner, e.type.label].join(' \u00b7 '),
                    style: AppText.secondary.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const DetailIcon(Icons.schedule),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DetailLines(
                      DateFormat.yMMMMEEEEd().format(e.startsAt),
                      eventTimeRange(e),
                    ),
                  ),
                ],
              ),
              if (e.series case final series?) ...[
                const SizedBox(height: 8),
                RepeatNote(series: series),
              ],
              if (e.location.isNotEmpty) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => showDirectionsSheet(context, place: e.location),
                  borderRadius: BorderRadius.circular(controlRadius),
                  child: Row(
                    children: [
                      const DetailIcon(Icons.place_outlined),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: DetailLines(e.location, null)),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 0, 12),
                          child: Text(
                            'Directions',
                            textAlign: TextAlign.end,
                            style: AppText.label.copyWith(color: c.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (calendarButton case final button?) ...[
                const SizedBox(height: 14),
                button,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A field-coloured icon tile, beside [DetailLines] in a summary card.
class DetailIcon extends StatelessWidget {
  const DetailIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: 48,
      height: 44,
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Icon(icon, color: c.ink2),
    );
  }
}

/// A bold line over a muted one, beside a badge or icon tile.
class DetailLines extends StatelessWidget {
  const DetailLines(this.title, this.subtitle, {super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.bodyStrong.copyWith(color: c.ink)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: AppText.secondary.copyWith(color: c.muted)),
        ],
      ],
    );
  }
}

/// An event's notes, in a card of their own.
class EventNotes extends StatelessWidget {
  const EventNotes({super.key, required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader('Notes'),
      Text(
        notes,
        style: AppText.body.copyWith(color: AppColors.of(context).ink2),
      ),
    ],
  );
}

class _RsvpSection extends StatelessWidget {
  const _RsvpSection({required this.viewModel});

  final EventDetailViewModel viewModel;

  // The screen rebuilds on the view model; the buttons also follow the
  // commands, or they stay off after a save finishes.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([viewModel.setRsvp, viewModel.saveNote]),
    builder: (context, _) => _section(context),
  );

  Widget _section(BuildContext context) {
    final vm = viewModel;
    final r = vm.responses;
    final type = vm.event?.type ?? EventType.other;
    final going = r[RsvpStatus.going]!.length;
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: SectionHeader('Are you in?')),
              if (vm.needsRsvp) const NeedsYouPill('Needs RSVP'),
            ],
          ),
          // How many are coming, in words.
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(
              going == 1 ? '1 person going' : '$going people going',
              style: AppText.secondary.copyWith(
                color: AppColors.of(context).muted,
              ),
            ),
          ),
          RsvpChoice<RsvpStatus>(
            options: [
              for (final s in RsvpStatus.values)
                (value: s, label: s.labelFor(type), count: r[s]!.length),
            ],
            selected: vm.myRsvp,
            onChanged: vm.setRsvp.running ? null : vm.setRsvp.execute,
          ),
          // A note goes with an answer, and goes when it's taken back.
          if (vm.myRsvp != null) ...[
            const SizedBox(height: 10),
            RsvpNoteField(
              note: vm.myNote,
              onSave: vm.saveNote.running ? null : vm.saveNote.execute,
            ),
          ],
        ],
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
    final c = AppColors.of(context);
    final tally = vm.pollTally;
    final total = vm.event?.voterCount ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.poll_outlined, color: c.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    poll.question,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${poll.multiple ? 'Pick any' : 'Pick one'} · '
              '$total of ${vm.memberCount} voted',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
            const SizedBox(height: 12),
            for (final t in tally)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Tooltip(
                  message: t.voters.isEmpty ? 'No votes' : t.voters.join(', '),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(controlRadius),
                    onTap: vm.vote.running || !vm.canRespond
                        ? null
                        : () => vm.vote.execute(t.option.id),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(controlRadius),
                        border: Border.all(
                          color: t.mine ? c.accent : c.border2,
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
                              child: ColoredBox(color: c.accentSoft),
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
                                  color: t.mine ? c.accent : c.muted,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    t.option.text,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: t.mine
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: c.ink,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${t.voters.length}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: t.mine ? c.accentInk : c.ink2,
                                  ),
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
    final r = viewModel.responders;
    final type = viewModel.event?.type ?? EventType.other;
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Responses'),
          RsvpResponses(
            groups: [
              for (final s in RsvpStatus.values)
                (
                  label: s.labelFor(type),
                  people: r[s]!,
                  tone: s == RsvpStatus.going ? RsvpTone.yes : RsvpTone.other,
                ),
              (
                label: 'No reply',
                people: withoutNotes(viewModel.noResponse),
                tone: RsvpTone.none,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
