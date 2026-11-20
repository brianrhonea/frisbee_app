import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/team_page.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
import '../../schedule/widgets/event_style.dart';
import '../../schedule/widgets/rsvp_widgets.dart';

// The community page's own sections (redesign F27), shown on a pickup
// community's or a school or club's page: the next event with RSVP, the
// chat rooms and the organizers. The website's are in
// apps/web/components/team/CommunitySections.tsx.

/// The community's next event at the top of its page: date tile, title,
/// time, place and the Going count, with Going / Maybe / Can't go for
/// members (the event screen's control: tapping the picked answer takes it
/// back) and an amber "RSVP needed" while they haven't answered. Outsiders
/// see the event and [join] instead. With no [event], a quiet "No pickup
/// scheduled" and, for those who add events, New event.
class NextPickupCard extends StatelessWidget {
  const NextPickupCard({
    super.key,
    required this.kind,
    required this.event,
    required this.member,
    this.mine,
    this.needsRsvp = false,
    this.busy = false,
    this.onAnswer,
    this.onOpen,
    this.onNewEvent,
    this.join,
  });

  final TeamKind kind;
  final TeamEvent? event;
  final bool member;
  final RsvpStatus? mine;
  final bool needsRsvp;
  final bool busy;
  final ValueChanged<RsvpStatus?>? onAnswer;
  final VoidCallback? onOpen;
  final VoidCallback? onNewEvent;

  /// An outsider's Join / Ask to join prompt.
  final Widget? join;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = nextEventCardText(kind);
    final e = event;
    if (e == null) {
      return SectionCard(
        title: text.title,
        child: Row(
          children: [
            Icon(Icons.event_available_outlined, size: 20, color: c.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text.empty,
                style: TextStyle(fontSize: 13.5, color: c.muted),
              ),
            ),
            if (onNewEvent case final add?)
              TextButton.icon(
                onPressed: add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New event'),
              ),
          ],
        ),
      );
    }
    final count = <RsvpStatus, int>{
      for (final s in RsvpStatus.values) s: e.responders(s).length,
    };
    final going = count[RsvpStatus.going] ?? 0;
    return SectionCard(
      title: text.title,
      action: needsRsvp ? const NeedsYouPill('RSVP needed') : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(controlRadius),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  DateBadge(date: e.startsAt, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title.isEmpty ? 'Event' : e.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${DateFormat.MMMEd().format(e.startsAt)} · '
                          '${eventTimeRange(e)}',
                          style: TextStyle(fontSize: 12.5, color: c.ink2),
                        ),
                        if (e.location.isNotEmpty)
                          Text(
                            e.location,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: c.muted),
                          ),
                        // Outsiders read the public copy, which has no answers.
                        if (member)
                          Text(
                            '$going going',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: c.accentInk,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: c.muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (member)
            RsvpChoice<RsvpStatus>(
              options: [
                for (final s in RsvpStatus.values)
                  (value: s, label: s.label, count: count[s] ?? 0),
              ],
              selected: mine,
              onChanged: busy ? null : onAnswer,
            )
          else
            ?join,
        ],
      ),
    );
  }
}

/// An outsider's way in, on the next pickup card: Join an open community,
/// Ask to join one that approves members, or Cancel request while it
/// waits (the same paths as the page's join card).
class PickupJoinPrompt extends StatelessWidget {
  const PickupJoinPrompt({
    super.key,
    required this.requiresApproval,
    required this.pending,
    required this.busy,
    required this.onJoin,
    required this.onCancel,
  });

  final bool requiresApproval;
  final bool pending;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(switch ((pending, requiresApproval)) {
            (true, _) => 'Request sent. An admin will let you in soon.',
            (false, true) => 'Ask to join to RSVP and see who is going.',
            (false, false) => 'Join the community to RSVP.',
          }, style: TextStyle(fontSize: 13, color: c.ink2)),
        ),
        const SizedBox(width: 12),
        if (pending)
          OutlinedButton(
            onPressed: busy ? null : onCancel,
            child: const Text('Cancel request'),
          )
        else
          FilledButton(
            onPressed: busy ? null : onJoin,
            child: Text(requiresApproval ? 'Ask to join' : 'Join'),
          ),
      ],
    );
  }
}

/// The community's chat rooms the member can read, unread ones first with
/// an amber dot (theirs to read), each opening its room; All chat opens
/// the chat page.
class CommunityChatSection extends StatelessWidget {
  const CommunityChatSection({
    super.key,
    required this.rooms,
    required this.more,
    required this.onOpenRoom,
    required this.onOpenChat,
  });

  final List<({ChatRoom room, bool unread})> rooms;
  final int more;
  final ValueChanged<ChatRoom> onOpenRoom;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SectionCard(
      title: 'Chat rooms',
      action: CardLink(
        label: more > 0 ? 'All chat (+$more)' : 'All chat',
        onTap: onOpenChat,
      ),
      child: rooms.isEmpty
          ? Text(
              'No rooms yet.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (:room, :unread) in rooms)
                  Semantics(
                    button: true,
                    label:
                        '#${room.handle}'
                        '${unread ? ', new messages' : ''}',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onOpenRoom(room),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.tag, size: 18, color: c.muted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                room.handle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: unread ? c.ink : c.ink2,
                                ),
                              ),
                            ),
                            if (unread)
                              Container(
                                key: ValueKey('unread-${room.id}'),
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: c.highlight,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right, size: 18, color: c.muted),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The community's owner and those who run it, each with Message (the
/// direct-message flow) for everyone but the member themselves.
class CommunityOrganizersSection extends StatelessWidget {
  const CommunityOrganizersSection({
    super.key,
    required this.organizers,
    required this.me,
    required this.onMessage,
    this.busy = false,
  });

  final List<CommunityOrganizer> organizers;
  final String me;

  /// Null when messages can't be opened from here.
  final ValueChanged<CommunityOrganizer>? onMessage;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SectionCard(
      title: 'Organizers',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in organizers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  PersonAvatar(name: o.name, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.uid == me ? '${o.name} (you)' : o.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        Eyebrow(o.label),
                      ],
                    ),
                  ),
                  if (o.uid != me && onMessage != null)
                    OutlinedButton.icon(
                      key: ValueKey('message-${o.uid}'),
                      onPressed: busy ? null : () => onMessage!(o),
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('Message'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
