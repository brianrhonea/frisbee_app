import 'package:flutter/material.dart';

import '../../../domain/models/team_page.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../view_models/team_home_viewmodel.dart';

/// What the team page's Message sheet picked.
sealed class MessageChoice {
  const MessageChoice();
}

/// The team's chat (members only).
class TeamChatChoice extends MessageChoice {
  const TeamChatChoice();
}

/// A direct conversation with one of the team's staff.
class StaffChoice extends MessageChoice {
  const StaffChoice(this.staff);

  final CommunityOrganizer staff;
}

/// The team page's Message sheet: members get "Team chat" first, then the
/// team's staff (owner, admins, coaches), each with a Message button that
/// opens a direct conversation. Outsiders see just the staff. Completes
/// with the choice, or null when dismissed.
Future<MessageChoice?> showTeamMessageSheet(
  BuildContext context,
  TeamHomeViewModel vm,
) => showModalBottomSheet<MessageChoice>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  sheetAnimationStyle: AppMotion.sheetStyle(context),
  builder: (_) =>
      TeamMessageSheet(staff: vm.messageableStaff, teamChat: vm.isMember),
);

class TeamMessageSheet extends StatelessWidget {
  const TeamMessageSheet({
    super.key,
    required this.staff,
    required this.teamChat,
  });

  final List<CommunityOrganizer> staff;

  /// Whether to offer the team's chat (the user is a member).
  final bool teamChat;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            0,
            AppSpace.lg,
            AppSpace.lg,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Semantics(
                header: true,
                child: Text(
                  'Message',
                  style: AppText.section.copyWith(color: c.ink),
                ),
              ),
            ),
            if (teamChat)
              ListTile(
                key: const ValueKey('team-chat'),
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: 12,
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Team chat'),
                subtitle: const Text('Everyone on the team'),
                onTap: () => Navigator.pop(context, const TeamChatChoice()),
              ),
            if (staff.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpace.sm,
                  bottom: AppSpace.xs,
                ),
                child: const Eyebrow('Staff'),
              ),
            for (final o in staff)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Row(
                  children: [
                    PersonAvatar(name: o.name, radius: 18),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodyStrong.copyWith(color: c.ink),
                          ),
                          Text(
                            o.label,
                            style: AppText.caption.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      key: ValueKey('message-${o.uid}'),
                      onPressed: () => Navigator.pop(context, StaffChoice(o)),
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('Message'),
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
