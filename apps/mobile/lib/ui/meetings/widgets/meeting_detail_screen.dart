import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/meeting.dart';
import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show DateBadge, SectionCard;
import '../../core/ui/scoreboard.dart' show NeedsYouPill, TeamDot;
import '../../core/ui/status_views.dart';
import '../../schedule/widgets/event_detail_screen.dart'
    show DetailIcon, DetailLines;
import '../../schedule/widgets/event_style.dart';
import '../../schedule/widgets/rsvp_widgets.dart';
import '../view_models/meeting_detail_viewmodel.dart';
import '../../core/ui/status_pill.dart';

class MeetingDetailScreen extends StatefulWidget {
  const MeetingDetailScreen({super.key, required this.viewModel});

  final MeetingDetailViewModel viewModel;

  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  MeetingDetailViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [
    vm.setRsvp,
    vm.saveNote,
    vm.deleteMeeting,
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
    if (vm.deleteMeeting.completed) {
      vm.deleteMeeting.clearResult();
      context.canPop()
          ? context.pop()
          : context.go(Routes.teamEvents(vm.teamId));
      return;
    }
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  Future<void> _delete(TeamMeeting m) async {
    if (await confirmDialog(
      context,
      title: 'Delete "${m.title}"?',
      message: m.isLive
          ? 'The meeting is live. Everyone in it will be disconnected.'
          : 'RSVPs and the meeting chat will be lost.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.deleteMeeting.execute();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final m = vm.meeting;
      final back = backOr(context, Routes.teamEvents(vm.teamId));
      if (!vm.loaded) {
        return Scaffold(
          appBar: AppBar(leading: back),
          body: const LoadingState(),
        );
      }
      if (m == null) {
        return Scaffold(
          appBar: AppBar(leading: back),
          body: vm.error != null
              ? ErrorState(error: vm.error)
              : const EmptyState(
                  icon: Icons.videocam_off_outlined,
                  title: 'Meeting not available',
                  message: "It may have been deleted, or you weren't invited.",
                ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          leading: back,
          title: const Text('Meeting'),
          actions: [
            if (vm.canEdit) ...[
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    context.push(Routes.editMeeting(vm.teamId, vm.meetingId)),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(m),
              ),
            ],
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                _Header(
                  meeting: m,
                  teamName: vm.teamName,
                  needsApproval: vm.needsApproval,
                  roomButton: m.isEnded
                      ? null
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () => context.push(
                            Routes.meetingRoom(vm.teamId, vm.meetingId),
                          ),
                          icon: const Icon(Icons.meeting_room_outlined),
                          label: Text(
                            m.isLive
                                ? 'Join meeting room'
                                : 'Go to meeting room',
                          ),
                        ),
                ),
                if (m.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'Agenda',
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      m.notes,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.of(context).ink2,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (!m.isEnded) ...[
                  _RsvpCard(viewModel: vm),
                  const SizedBox(height: 12),
                ],
                _Responses(viewModel: vm),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.meeting,
    required this.teamName,
    required this.needsApproval,
    required this.roomButton,
  });

  final TeamMeeting meeting;
  final String? teamName;
  final bool needsApproval;

  /// "Go to meeting room", until the meeting ends.
  final Widget? roomButton;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final m = meeting;
    return SectionCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TeamDot(color: c.team),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [?teamName, EventType.meeting.label].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                ),
              ),
              if (m.isLive || m.isEnded) MeetingStatusBadge(meeting: m),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            m.title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.2,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              DateBadge(date: m.startsAt, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: DetailLines(
                  DateFormat.yMMMMEEEEd().format(m.startsAt),
                  eventTimeRange(m.toEvent()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const DetailIcon(Icons.groups_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: DetailLines(
                  m.audience,
                  m.requireApproval
                      ? (needsApproval
                            ? 'An admin lets you in once you ask to join.'
                            : 'Invitees wait for an admin to let them in.')
                      : 'Invitees can join once it starts.',
                ),
              ),
            ],
          ),
          if (roomButton case final button?) ...[
            const SizedBox(height: 14),
            button,
          ],
        ],
      ),
    );
  }
}

/// "Live" or "Ended", for headers and the room: a [StatusPill].
class MeetingStatusBadge extends StatelessWidget {
  const MeetingStatusBadge({super.key, required this.meeting});

  final TeamMeeting meeting;

  @override
  Widget build(BuildContext context) =>
      // A live meeting is the app's accent: red is only for live games.
      meeting.isLive
      ? const StatusPill('Live', tone: PillTone.accent, dot: true)
      : const StatusPill('Ended', icon: Icons.check);
}

class _RsvpCard extends StatelessWidget {
  const _RsvpCard({required this.viewModel});

  final MeetingDetailViewModel viewModel;

  // The buttons follow the commands too, or they stay off after a save.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([viewModel.setRsvp, viewModel.saveNote]),
    builder: (context, _) => _card(context),
  );

  Widget _card(BuildContext context) {
    final vm = viewModel;
    final r = vm.responses;
    return SectionCard(
      title: 'Will you attend?',
      action: vm.needsRsvp ? const NeedsYouPill('Needs RSVP') : null,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RsvpChoice<MeetingRsvp>(
            options: [
              for (final a in MeetingRsvp.values)
                (value: a, label: a.label, count: r[a]!.length),
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
          const SizedBox(height: 8),
          Text(
            vm.myRsvp == MeetingRsvp.attending
                ? "We'll notify you when it starts."
                : 'Attending? You get a notification when it starts.',
            style: TextStyle(fontSize: 12, color: AppColors.of(context).muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Responses extends StatelessWidget {
  const _Responses({required this.viewModel});

  final MeetingDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final r = viewModel.responders;
    return SectionCard(
      title: 'Invited (${viewModel.inviteeCount})',
      padding: const EdgeInsets.all(14),
      child: RsvpResponses(
        groups: [
          for (final a in MeetingRsvp.values)
            (
              label: a.label,
              people: r[a]!,
              tone: a == MeetingRsvp.attending ? RsvpTone.yes : RsvpTone.other,
            ),
          (
            label: 'No reply',
            people: withoutNotes(viewModel.noResponse),
            tone: RsvpTone.none,
          ),
        ],
      ),
    );
  }
}
