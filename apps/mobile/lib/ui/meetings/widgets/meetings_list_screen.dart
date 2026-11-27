import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/meeting.dart';
import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/layout.dart' show DateBadge;
import '../../core/ui/scoreboard.dart' show NeedsYouPill;
import '../../core/ui/status_views.dart';
import '../../schedule/widgets/rsvp_widgets.dart' show RsvpStatusPill;
import '../view_models/meetings_list_viewmodel.dart';
import 'meeting_detail_screen.dart' show MeetingStatusBadge;

/// A team's meetings (the website's Meetings list): live ones first with
/// Join, then Upcoming or Past. Each row has its date tile, title, time
/// and who's invited, and the user's answer ("Needs RSVP" in amber while
/// it's theirs to answer). Admins schedule new ones.
class MeetingsListScreen extends StatelessWidget {
  const MeetingsListScreen({super.key, required this.viewModel});

  final MeetingsListViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      final c = AppColors.of(context);
      final back = backOr(context, Routes.teamEvents(vm.teamId));
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Meetings'),
          if (vm.teamName case final name?)
            Text(name, style: TextStyle(fontSize: 12.5, color: c.muted)),
        ],
      );
      final Widget body;
      if (!vm.loaded) {
        body = const LoadingState();
      } else if (vm.error != null) {
        body = ErrorState(error: vm.error);
      } else if (!vm.isMember) {
        body = const EmptyState(
          icon: Icons.lock_outline,
          title: 'Members only',
          message: "Only the team's members see its meetings.",
        );
      } else if (!vm.meetingsOn) {
        body = const EmptyState(
          icon: Icons.videocam_off_outlined,
          title: 'Meetings are off',
          message: 'The owner can turn them on in Settings › Sections.',
        );
      } else {
        body = _List(viewModel: vm);
      }
      return Scaffold(
        appBar: AppBar(
          leading: back,
          title: title,
          actions: [
            if (vm.loaded && vm.meetingsOn && vm.canCreate)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => context.push(Routes.newMeeting(vm.teamId)),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('New meeting'),
                ),
              ),
          ],
        ),
        body: body,
      );
    },
  );
}

class _List extends StatelessWidget {
  const _List({required this.viewModel});

  final MeetingsListViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final shown = vm.showPast ? vm.past : vm.upcoming;
    final live = vm.showPast ? const <TeamMeeting>[] : vm.live;
    return ConstrainedContent(
      maxWidth: 720,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _PastSwitch(past: vm.showPast, onChanged: vm.setShowPast),
          if (live.isNotEmpty) ...[
            const _Heading('Live now'),
            _Rows(viewModel: vm, meetings: live, live: true),
          ],
          _Heading(
            vm.showPast ? 'Past meetings' : 'Coming up',
            count: shown.length,
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: EmptyState(
                icon: Icons.videocam_outlined,
                title: vm.showPast
                    ? 'No past meetings'
                    : 'No meetings scheduled',
                message: !vm.showPast && vm.canCreate
                    ? 'Schedule one for film, planning or a chat.'
                    : null,
              ),
            )
          else
            _Rows(viewModel: vm, meetings: shown),
        ],
      ),
    );
  }
}

/// Upcoming / Past, as a segmented track.
class _PastSwitch extends StatelessWidget {
  const _PastSwitch({required this.past, required this.onChanged});

  final bool past;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget tab(String label, bool value) {
      final on = value == past;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: Material(
            color: on ? c.card : Colors.transparent,
            borderRadius: BorderRadius.circular(controlRadius - 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(controlRadius - 2),
              onTap: () => onChanged(value),
              child: SizedBox(
                height: 38,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                      color: on ? c.ink : c.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Row(children: [tab('Upcoming', false), tab('Past', true)]),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.count});

  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
              color: c.ink2,
            ),
          ),
          if (count case final n? when n > 0) ...[
            const SizedBox(width: 8),
            Text(
              n == 1 ? '1 meeting' : '$n meetings',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// [meetings] as rows on one card.
class _Rows extends StatelessWidget {
  const _Rows({
    required this.viewModel,
    required this.meetings,
    this.live = false,
  });

  final MeetingsListViewModel viewModel;
  final List<TeamMeeting> meetings;
  final bool live;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (i, m) in meetings.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _MeetingRow(viewModel: viewModel, meeting: m, live: live),
        ],
      ],
    ),
  );
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({
    required this.viewModel,
    required this.meeting,
    required this.live,
  });

  final MeetingsListViewModel viewModel;
  final TeamMeeting meeting;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final m = meeting;
    final time = DateFormat.jm().format(m.startsAt);
    final going = vm.attendingCount(m);
    final meta = [
      if (m.isEnded) 'Ended' else time,
      m.audience,
      if (!m.isEnded && going > 0) '$going going',
    ].join(' · ');
    final answer = vm.myRsvp(m);
    final Widget? trailing = live
        ? FilledButton(
            onPressed: () => context.push(Routes.meetingRoom(vm.teamId, m.id)),
            child: const Text('Join'),
          )
        : m.isEnded
        ? null
        : vm.needsRsvp(m)
        ? const NeedsYouPill('Needs RSVP')
        : answer != null
        ? RsvpStatusPill(status: answer.asEventRsvp, type: EventType.meeting)
        : null;
    return InkWell(
      onTap: () => context.push(Routes.meeting(vm.teamId, m.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            DateBadge(date: m.startsAt, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.title.isEmpty ? 'Meeting' : m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                      if (m.isLive) ...[
                        const SizedBox(width: 8),
                        MeetingStatusBadge(meeting: m),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing],
          ],
        ),
      ),
    );
  }
}
