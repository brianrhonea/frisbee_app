import 'dart:math';

import '../models/group_tournament.dart';

/// Someone who can be put on a team.
typedef TournamentPlayer = ({String uid, String name});

/// Deals [players] at random into teams of about [teamSize]: as many
/// teams as it takes to fit everyone, with sizes differing by at most one.
/// Each team gets a random captain and the name "Team n".
List<TournamentTeam> buildTeams(
  List<TournamentPlayer> players, {
  required int teamSize,
  Random? random,
}) {
  final unique = {for (final p in players) p.uid: p}.values.toList()
    ..shuffle(random);
  if (unique.isEmpty || teamSize < 1) return const [];
  final count = max(2, (unique.length / teamSize).ceil());
  final rosters = List.generate(count, (_) => <TournamentPlayer>[]);
  for (var i = 0; i < unique.length; i++) {
    rosters[i % count].add(unique[i]);
  }
  return [
    for (var i = 0; i < count; i++)
      TournamentTeam(
        id: 'team${i + 1}',
        name: 'Team ${i + 1}',
        // Players were shuffled, so the first is a random pick.
        captainId: rosters[i].firstOrNull?.uid,
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
