// Splitting a team fee (packages/shared/src/team_share.ts): someone who
// paid for the whole team (a league's team fee, say) sets each member's
// share and how to pay them (Venmo, cash…), and marks who has paid. No
// money passes through Stall 10.

/// Each share is at most $100,000 (teamShareLimits).
const teamShareMaxCents = 10000000;

/// How to pay, at most this long.
const teamShareNoteMax = 300;

class TeamShareMember {
  const TeamShareMember({
    required this.uid,
    required this.name,
    required this.paid,
  });

  factory TeamShareMember.fromJson(Map<String, Object?> j) => TeamShareMember(
    uid: j['uid'] as String? ?? '',
    name: j['name'] as String? ?? 'Member',
    paid: j['paid'] == true,
  );

  final String uid;
  final String name;
  final bool paid;
}

class TeamShare {
  const TeamShare({
    required this.amountCents,
    required this.currency,
    required this.note,
    required this.collectorId,
    required this.collectorName,
  });

  factory TeamShare.fromJson(Map<String, Object?> j) => TeamShare(
    amountCents: (j['amountCents'] as num?)?.toInt() ?? 0,
    currency: j['currency'] as String? ?? 'usd',
    note: j['note'] as String? ?? '',
    collectorId: j['collectorId'] as String? ?? '',
    collectorName: j['collectorName'] as String? ?? "the team's admin",
  );

  final int amountCents;
  final String currency;

  /// How to pay the collector (Venmo, cash…).
  final String note;

  /// Who collects (who set it up); everyone else owes a share.
  final String collectorId;
  final String collectorName;
}

/// `GET /v1/teams/:id/share` (TeamShareView in team_share.ts).
class TeamShareView {
  const TeamShareView({
    this.share,
    this.manages = false,
    this.mine,
    this.members = const [],
  });

  factory TeamShareView.fromJson(Map<String, Object?> j) {
    final share = j['share'];
    final mine = j['mine'];
    return TeamShareView(
      share: share is Map
          ? TeamShare.fromJson(share.cast<String, Object?>())
          : null,
      manages: j['manages'] == true,
      mine: mine is Map ? mine['paid'] == true : null,
      members: [
        for (final m in (j['members'] as List?) ?? const [])
          if (m is Map) TeamShareMember.fromJson(m.cast<String, Object?>()),
      ],
    );
  }

  static const none = TeamShareView();

  final TeamShare? share;

  /// Whether the viewer can change it and mark people paid.
  final bool manages;

  /// Whether the viewer has paid their own share; null when they collect
  /// it (or there's none).
  final bool? mine;

  /// Everyone who owes a share, for those who manage it.
  final List<TeamShareMember> members;
}

/// Collected and still owed (shareTotals in team_share.ts).
({int paid, int owed, int collectedCents, int outstandingCents}) shareTotals(
  int amountCents,
  List<TeamShareMember> members,
) {
  final paid = members.where((m) => m.paid).length;
  final owed = members.length - paid;
  return (
    paid: paid,
    owed: owed,
    collectedCents: paid * amountCents,
    outstandingCents: owed * amountCents,
  );
}

/// An even share of [totalCents] among [people], rounded up to the cent
/// (evenShare in team_share.ts).
int evenShare(int totalCents, int people) {
  if (people <= 0 || totalCents <= 0) return 0;
  return (totalCents + people - 1) ~/ people;
}

/// "$40" or "$40.50".
String shareMoney(int cents) =>
    '\$${(cents / 100).toStringAsFixed(cents % 100 == 0 ? 0 : 2)}';

/// Cents from what someone typed ("40", "\$40.50"), or null.
int? parseShareCents(String typed) {
  final v = double.tryParse(typed.trim().replaceAll(r'$', ''));
  if (v == null || v <= 0) return null;
  final cents = (v * 100).round();
  return cents > teamShareMaxCents ? null : cents;
}
