import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/meeting.dart';
import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../schedule/widgets/event_style.dart';
import '../view_models/meeting_detail_viewmodel.dart';

class MeetingDetailScreen extends StatefulWidget {
  const MeetingDetailScreen({super.key, required this.viewModel});

  final MeetingDetailViewModel viewModel;

  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  MeetingDetailViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [vm.setRsvp, vm.deleteMeeting];

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
          body: const LoadingView(),
        );
      }
      if (m == null) {
        return Scaffold(
          appBar: AppBar(leading: back),
          body: vm.error != null
              ? ErrorView(error: vm.error)
              : const EmptyView(
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Header(meeting: m, needsApproval: vm.needsApproval),
                const SizedBox(height: 16),
                if (!m.isEnded)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => context.push(
                      Routes.meetingRoom(vm.teamId, vm.meetingId),
                    ),
                    icon: const Icon(Icons.meeting_room_outlined),
                    label: Text(
                      m.isLive ? 'Join meeting room' : 'Go to meeting room',
                    ),
                  ),
                const SizedBox(height: 20),
                if (!m.isEnded) ...[
                  _RsvpCard(viewModel: vm),
                  const SizedBox(height: 20),
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
  const _Header({required this.meeting, required this.needsApproval});

  final TeamMeeting meeting;
  final bool needsApproval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = meeting;
    final color = EventType.meeting.color(theme.colorScheme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              foregroundColor: color,
              child: Icon(EventType.meeting.icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(m.title, style: theme.textTheme.headlineSmall),
            ),
            if (m.isLive || m.isEnded) MeetingStatusBadge(meeting: m),
          ],
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(DateFormat.yMMMMEEEEd().format(m.startsAt)),
          subtitle: Text(eventTimeRange(m.toEvent())),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.groups_outlined),
          title: Text(m.audience),
          subtitle: Text(
            m.requireApproval
                ? (needsApproval
                      ? 'An admin lets you in once you ask to join.'
                      : 'Invitees wait for an admin to let them in.')
                : 'Invitees can join once it starts.',
          ),
        ),
        if (m.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(m.notes, style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// "Live" or "Ended", for headers and the room.
class MeetingStatusBadge extends StatelessWidget {
  const MeetingStatusBadge({super.key, required this.meeting});

  final TeamMeeting meeting;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = meeting.isLive;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        live ? Icons.circle : Icons.check,
        size: 12,
        color: live ? Colors.red : scheme.outline,
      ),
      label: Text(live ? 'Live' : 'Ended'),
    );
  }
}

class _RsvpCard extends StatelessWidget {
  const _RsvpCard({required this.viewModel});

  final MeetingDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final r = vm.responses;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Will you attend?', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<MeetingRsvp>(
              segments: [
                for (final a in MeetingRsvp.values)
                  ButtonSegment(
                    value: a,
                    label: Text(a.label),
                    icon: Icon(a.asEventRsvp.icon),
                  ),
              ],
              selected: {?vm.myRsvp},
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              onSelectionChanged: vm.setRsvp.running
                  ? null
                  : (s) => vm.setRsvp.execute(s.firstOrNull),
            ),
            const SizedBox(height: 8),
            Text(
              vm.myRsvp == MeetingRsvp.attending
                  ? "We'll notify you when it starts."
                  : 'Attending? You get a notification when it starts.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              [
                for (final a in MeetingRsvp.values)
                  '${r[a]!.length} ${a.label.toLowerCase()}',
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

class _Responses extends StatelessWidget {
  const _Responses({required this.viewModel});

  final MeetingDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = viewModel.responses;
    final groups = [
      for (final a in MeetingRsvp.values)
        (a.label, a.asEventRsvp.icon, a.asEventRsvp.color(scheme), r[a]!),
      ('No reply', Icons.hourglass_empty, scheme.outline, viewModel.noResponse),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invited (${viewModel.inviteeCount})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final (label, icon, color, names) in groups)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: Icon(icon, color: color),
            title: Text('$label (${names.length})'),
            initiallyExpanded: label == MeetingRsvp.attending.label,
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
