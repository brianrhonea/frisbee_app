// Online payments for tournament and league fees (Stripe Connect). The
// server's answers, as in packages/shared/src/payments.ts.

/// Where a host's Stripe account stands.
enum PayoutStatus {
  /// Not connected.
  none,

  /// Connected, but Stripe still needs details before it can take payments.
  pending,

  /// Takes payments.
  ready;

  static PayoutStatus parse(Object? v) => switch (v) {
    'pending' => pending,
    'ready' => ready,
    _ => none,
  };
}

/// A host's payout account (`GET /v1/teams/:id/payouts`, owners only).
class PayoutAccount {
  const PayoutAccount({
    required this.available,
    required this.status,
    required this.feeLabel,
  });

  /// Not available: this server doesn't take payments yet; hide the section.
  static const unavailable = PayoutAccount(
    available: false,
    status: PayoutStatus.none,
    feeLabel: '',
  );

  final bool available;
  final PayoutStatus status;

  /// Stall 10's fee, e.g. "1% + $1".
  final String feeLabel;

  factory PayoutAccount.fromMap(Map<String, Object?> m) => PayoutAccount(
    available: m['available'] == true,
    status: PayoutStatus.parse(m['status']),
    feeLabel: m['feeLabel'] as String? ?? '',
  );
}

/// Whether the caller can pay a fee online (`GET /v1/tournaments/:id/pay`).
class PayOptions {
  const PayOptions({
    required this.online,
    required this.amountCents,
    required this.feeCents,
    required this.feeLabel,
    required this.paid,
    this.reason,
  });

  /// The host takes payments through Stall 10 and this fee can be paid online.
  final bool online;
  final int amountCents;

  /// Stall 10's part of the amount (included, not added).
  final int feeCents;
  final String feeLabel;
  final bool paid;

  /// Why it can't be paid online, when it can't.
  final String? reason;

  factory PayOptions.fromMap(Map<String, Object?> m) => PayOptions(
    online: m['online'] == true,
    amountCents: (m['amountCents'] as num?)?.toInt() ?? 0,
    feeCents: (m['feeCents'] as num?)?.toInt() ?? 0,
    feeLabel: m['feeLabel'] as String? ?? '',
    paid: m['paid'] == true,
    reason: m['reason'] as String?,
  );
}

/// "$400", "$1.60" (centsLabel in packages/shared).
String centsLabel(int cents) {
  final whole = cents ~/ 100;
  final rest = cents % 100;
  return rest == 0 ? '\$$whole' : '\$$whole.${rest.toString().padLeft(2, '0')}';
}
