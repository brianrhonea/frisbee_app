// The team page's More list, worded as on the website (team_page.ts in
// packages/shared).

import 'chat.dart';
import 'team.dart';

/// One line under each More row, by section path (`playbook`, `videos`,
/// `stats`, `tournaments`, `meetings`, `manage`): what's there. A count
/// would cost a read per row. Empty for anything else.
String teamMoreSubtitle(String row) => switch (row) {
  'playbook' => 'Plays and whiteboards',
  'videos' => 'Game film and highlights',
  'stats' => 'Games, lines and player stats',
  'tournaments' => 'Events your team has entered',
  'meetings' => 'Video calls with the team',
  'manage' => 'Details, sections and visibility',
  _ => '',
};

/// The More row that opens Settings, for admins.
String manageRowLabel({required bool group}) =>
    group ? 'Manage group' : 'Manage team';

// The community page (redesign F27): its chat and organizers sections,
// as chatSectionRooms and communityOrganizers in packages/shared.

/// Rooms the community page's chat section lists before "All chat".
const chatSectionMax = 5;

/// The chat section's rooms: the [unread] ones first (newest first, as
/// TeamChatSummary sorts them), each marked, then the rest of [rooms] in
/// the team's order, up to [max]; `more` is how many are left over.
({List<({ChatRoom room, bool unread})> rooms, int more}) chatSectionRooms(
  List<ChatRoom> rooms,
  List<ChatRoom> unread, {
  int max = chatSectionMax,
}) {
  final unreadIds = {for (final r in unread) r.id};
  final all = [
    for (final r in unread) (room: r, unread: true),
    for (final r in rooms)
      if (!unreadIds.contains(r.id)) (room: r, unread: false),
  ];
  return (
    rooms: all.take(max).toList(),
    more: all.length > max ? all.length - max : 0,
  );
}

/// Permissions that make a member one of a community's organizers:
/// running it, its members or its events. Chat moderators alone aren't
/// listed.
const organizerPermissions = {
  TeamPermission.manageTeam,
  TeamPermission.manageMembers,
  TeamPermission.manageEvents,
};

/// One person in the community page's Organizers section.
typedef CommunityOrganizer = ({String uid, String name, String label});

/// [team]'s organizers: the owner, then everyone else who can run it (a
/// coach or captain tier, or [organizerPermissions] from their roles or
/// their own switches), by name. Labelled "Owner", by tier ("Organizer"
/// for a captain), or by the preset their permissions match ("Admin",
/// "Organizer"), else "Organizer".
List<CommunityOrganizer> communityOrganizers(Team team) {
  final out = <({CommunityOrganizer o, bool owner})>[];
  for (final MapEntry(key: uid, value: role) in team.members.entries) {
    final known = team.memberNames[uid] ?? '';
    final name = known.isEmpty ? 'Member' : known;
    switch (role) {
      case TeamRole.owner:
        out.add((o: (uid: uid, name: name, label: 'Owner'), owner: true));
      case TeamRole.coach || TeamRole.captain:
        out.add((
          o: (uid: uid, name: name, label: role.labelFor(TeamKind.community)),
          owner: false,
        ));
      case TeamRole.player:
        final perms = team.memberPerms[uid] ?? const <TeamPermission>{};
        if (!perms.any(organizerPermissions.contains)) continue;
        final preset = RolePreset.matching(perms, true);
        out.add((
          o: (uid: uid, name: name, label: preset?.name ?? 'Organizer'),
          owner: false,
        ));
    }
  }
  out.sort((a, b) {
    if (a.owner != b.owner) return a.owner ? -1 : 1;
    final byName = a.o.name.compareTo(b.o.name);
    return byName != 0 ? byName : a.o.uid.compareTo(b.o.uid);
  });
  return [for (final e in out) e.o];
}

/// The community page's next-event card (F27): its title and what it says
/// when nothing's ahead. A pickup community's events are pickups; a
/// school or club's are anything.
({String title, String empty}) nextEventCardText(TeamKind kind) =>
    kind == TeamKind.organization
    ? (title: 'Next event', empty: 'No events scheduled')
    : (title: 'Next pickup', empty: 'No pickup scheduled');

/// Who the Message sheet offers: the members whose tier is owner, coach or
/// captain (never a permission-based admin or a stats keeper), labelled by
/// the team's kind ("Captain" on a team), sorted owner, coach, captain,
/// then by name. A person without a uid cannot be messaged and is dropped.
/// The outsider path (the roster endpoint) uses the same rule.
List<CommunityOrganizer> messageStaffOf(
  Iterable<({String uid, String name, TeamRole tier})> people,
  TeamKind kind,
) {
  final staff = [
    for (final p in people)
      if (p.uid.isNotEmpty && p.tier != TeamRole.player) p,
  ];
  int rank(TeamRole r) => switch (r) {
    TeamRole.owner => 0,
    TeamRole.coach => 1,
    _ => 2,
  };
  staff.sort((a, b) {
    final byTier = rank(a.tier).compareTo(rank(b.tier));
    if (byTier != 0) return byTier;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.uid.compareTo(b.uid);
  });
  return [
    for (final p in staff)
      (
        uid: p.uid,
        name: p.name.isEmpty ? 'Member' : p.name,
        label: p.tier.labelFor(kind),
      ),
  ];
}

/// [messageStaffOf] for a team the user is a member of.
List<CommunityOrganizer> teamMessageStaff(Team team) => messageStaffOf([
  for (final MapEntry(key: uid, value: role) in team.members.entries)
    (uid: uid, name: team.memberNames[uid] ?? '', tier: role),
], team.kind);
