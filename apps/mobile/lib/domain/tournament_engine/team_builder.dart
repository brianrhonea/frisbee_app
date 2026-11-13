import 'dart:math';

import '../models/group_tournament.dart';
import '../models/hosted_tournament.dart';

/// Someone who can be put on a team.
typedef TournamentPlayer = ({String uid, String name});

/// A signed-up player to draft: [skill] is self-rated 1-5, and [gender] is
/// their match in mixed divisions (null if they didn't say).
typedef DraftPlayer = ({
  String uid,
  String name,
  int skill,
  GenderMatch? gender,
});

/// Drafts [players] onto [teams], replacing their rosters, so teams come
/// out even in size and in total skill. Strongest players go first, each
/// to the team that has the fewest players and, among those, the lowest
/// skill total, which makes the pick order snake back and forth.
///
/// With [mixed], each gender match is drafted as its own group so every
/// team gets about the same number of each; players with no gender match
/// go last, to whichever teams are short.
///
/// The same [seed] with the same players gives the same teams (it only
/// breaks ties between equally skilled players). Each team's captain is
/// its most skilled player.
List<TournamentTeam> balancedDraft(
  List<DraftPlayer> players,
  List<TournamentTeam> teams, {
  required int seed,
  bool mixed = false,
}) {
  if (teams.isEmpty) return const [];
  final random = Random(seed);
  final unique = {for (final p in players) p.uid: p}.values.toList()
    ..shuffle(random);
  // Strongest first; the shuffle above settles ties.
  final order = {for (var i = 0; i < unique.length; i++) unique[i].uid: i};
  unique.sort((a, b) {
    final bySkill = b.skill - a.skill;
    return bySkill != 0 ? bySkill : order[a.uid]! - order[b.uid]!;
  });

  final rosters = List.generate(teams.length, (_) => <DraftPlayer>[]);
  final skill = List.filled(teams.length, 0);
  final groups = mixed
      ? [GenderMatch.mmp, GenderMatch.wmp, null]
      : <GenderMatch?>[null];
  for (final group in groups) {
    final members = mixed
        ? [
            for (final p in unique)
              if (p.gender == group) p,
          ]
        : unique;
    final inGroup = List.filled(teams.length, 0);
    for (final p in members) {
      var best = 0;
      for (var t = 1; t < teams.length; t++) {
        final byGroup = mixed && group != null ? inGroup[t] - inGroup[best] : 0;
        final bySize = rosters[t].length - rosters[best].length;
        final bySkill = skill[t] - skill[best];
        final better = byGroup != 0
            ? byGroup < 0
            : bySize != 0
            ? bySize < 0
            : bySkill < 0;
        if (better) best = t;
      }
      rosters[best].add(p);
      inGroup[best]++;
      skill[best] += p.skill;
    }
  }

  return [
    for (var i = 0; i < teams.length; i++)
      teams[i].copyWith(
        captainId: () => _mostSkilled(rosters[i])?.uid,
        playerIds: [for (final p in rosters[i]) p.uid],
        playerNames: {for (final p in rosters[i]) p.uid: p.name},
      ),
  ];
}

/// The most skilled of [players]; the first listed wins a tie.
DraftPlayer? _mostSkilled(List<DraftPlayer> players) {
  DraftPlayer? best;
  for (final p in players) {
    if (best == null || p.skill > best.skill) best = p;
  }
  return best;
}

/// Deals [players] at random into [teams], replacing their rosters, so
/// team sizes differ by at most one. Names and ids stay; each team with
/// players gets a random captain.
List<TournamentTeam> dealPlayers(
  List<TournamentPlayer> players,
  List<TournamentTeam> teams, {
  Random? random,
}) {
  if (teams.isEmpty) return const [];
  final unique = {for (final p in players) p.uid: p}.values.toList()
    ..shuffle(random);
  final rosters = List.generate(teams.length, (_) => <TournamentPlayer>[]);
  for (var i = 0; i < unique.length; i++) {
    rosters[i % teams.length].add(unique[i]);
  }
  return [
    for (var i = 0; i < teams.length; i++)
      teams[i].copyWith(
        // Players were shuffled, so the first is a random pick.
        captainId: () => rosters[i].firstOrNull?.uid,
        playerIds: [for (final p in rosters[i]) p.uid],
        playerNames: {for (final p in rosters[i]) p.uid: p.name},
      ),
  ];
}

/// [count] empty teams named "Team 1" to "Team n", for organizers who
/// pick players by hand. Ids continue after any in [existing].
List<TournamentTeam> blankTeams(
  int count, {
  List<TournamentTeam> existing = const [],
}) {
  var next = existing.length + 1;
  final taken = {for (final t in existing) t.id};
  return [
    for (var i = 0; i < count; i++)
      () {
        while (taken.contains('team$next')) {
          next++;
        }
        final id = 'team$next';
        taken.add(id);
        return TournamentTeam(id: id, name: 'Team ${next++}');
      }(),
  ];
}

/// Moves [uid] onto [teamId] (off any other team), or off every team when
/// [teamId] is null. A captain who moves stops being captain; a team left
/// without one gets its first player.
List<TournamentTeam> movePlayer(
  List<TournamentTeam> teams,
  TournamentPlayer player, {
  required String? teamId,
}) => [
  for (final t in teams)
    if (t.id == teamId && !t.playerIds.contains(player.uid))
      t.copyWith(
        playerIds: [...t.playerIds, player.uid],
        playerNames: {...t.playerNames, player.uid: player.name},
        captainId: () => t.captainId ?? player.uid,
      )
    else if (t.id != teamId && t.playerIds.contains(player.uid))
      _without(t, player.uid)
    else
      t,
];

TournamentTeam _without(TournamentTeam t, String uid) {
  final ids = [...t.playerIds]..remove(uid);
  return t.copyWith(
    playerIds: ids,
    playerNames: {...t.playerNames}..remove(uid),
    captainId: () => t.captainId == uid ? ids.firstOrNull : t.captainId,
  );
}
