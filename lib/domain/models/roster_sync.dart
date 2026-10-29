import 'roster_player.dart';
import 'usau_team.dart';

/// Lowercase letters only, single spaces: "  O'Neil-Smith, Jr. " →
/// "oneilsmith jr".
String normalizeName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z\s]'), '')
    .trim()
    .split(RegExp(r'\s+'))
    .join(' ');

/// First and last name only, so a middle name on one side still matches.
String _firstLast(String normalized) {
  final parts = normalized.split(' ');
  return parts.length <= 2 ? normalized : '${parts.first} ${parts.last}';
}

/// What syncing the app roster with a USA Ultimate roster would change.
/// Players are matched by name. Nobody is removed; app players missing from
/// USA Ultimate are marked not on the roster.
class RosterSyncPlan {
  RosterSyncPlan._({
    required this.added,
    required this.matched,
    required this.missing,
    required Set<String> alreadyMissing,
  }) : _alreadyMissing = alreadyMissing;

  final Set<String> _alreadyMissing;

  /// USA Ultimate players new to the app roster.
  final List<RosterPlayer> added;

  /// App players found on USA Ultimate, updated with its number, position
  /// and roster status.
  final List<({RosterPlayer before, RosterPlayer after})> matched;

  /// App players not on the USA Ultimate roster, marked as such.
  final List<RosterPlayer> missing;

  /// Matched players whose number or position changes.
  Iterable<({RosterPlayer before, RosterPlayer after})> get updated =>
      matched.where(
        (m) =>
            m.before.number != m.after.number ||
            m.before.position != m.after.position,
      );

  /// Every roster document to write; unchanged players are skipped.
  List<RosterPlayer> get writes => [
    ...added,
    for (final m in matched)
      if (!_same(m.after, m.before)) m.after,
    for (final p in missing)
      if (!_alreadyMissing.contains(p.id)) p,
  ];

  static bool _same(RosterPlayer a, RosterPlayer b) =>
      a.number == b.number && a.position == b.position && a.onUsau == b.onUsau;

  factory RosterSyncPlan.build(
    List<RosterPlayer> roster,
    List<UsauPlayer> usau,
  ) {
    // USA Ultimate shows 0 for players without a number; only trust it when
    // a single player has it.
    final zeros = usau.where((p) => p.number.trim() == '0').length;
    int? numberOf(UsauPlayer p) =>
        p.number.trim() == '0' && zeros > 1 ? null : int.tryParse(p.number);
    PlayerPosition? positionOf(UsauPlayer p) {
      final pos = p.position.trim().toLowerCase();
      return PlayerPosition.values.where((v) => v.name == pos).firstOrNull;
    }

    final unmatched = [...roster];
    RosterPlayer? take(bool Function(RosterPlayer) test) {
      final i = unmatched.indexWhere(test);
      return i < 0 ? null : unmatched.removeAt(i);
    }

    final added = <RosterPlayer>[];
    final matched = <({RosterPlayer before, RosterPlayer after})>[];
    final pending = <UsauPlayer>[];
    // Exact names first so a looser match can't take someone else's player.
    for (final u in usau) {
      final key = normalizeName(u.name);
      final p = take((r) => normalizeName(r.name) == key);
      if (p == null) {
        pending.add(u);
      } else {
        matched.add((before: p, after: _apply(p, numberOf(u), positionOf(u))));
      }
    }
    for (final u in pending) {
      final key = _firstLast(normalizeName(u.name));
      final p = take((r) => _firstLast(normalizeName(r.name)) == key);
      if (p != null) {
        matched.add((before: p, after: _apply(p, numberOf(u), positionOf(u))));
      } else {
        added.add(
          RosterPlayer(
            id: '',
            name: u.name.trim(),
            number: numberOf(u),
            position: positionOf(u) ?? PlayerPosition.hybrid,
            onUsau: true,
          ),
        );
      }
    }
    return RosterSyncPlan._(
      added: added,
      matched: matched,
      missing: [for (final p in unmatched) p.copyWith(onUsau: false)],
      alreadyMissing: {
        for (final p in unmatched)
          if (p.onUsau == false) p.id,
      },
    );
  }

  static RosterPlayer _apply(
    RosterPlayer p,
    int? number,
    PlayerPosition? position,
  ) => p.copyWith(number: number, position: position, onUsau: true);
}
