/// A code, or a link's token, that joins a team until [expiresAt].
///
/// Short codes rotate: the app shows each one for [rotateEvery] and it
/// works for [codeLifetime], so someone typing it in has time to finish.
/// Links carry a longer token that lasts as long as [InviteLinkExpiry].
class InviteCode {
  const InviteCode({
    required this.code,
    required this.teamId,
    required this.expiresAt,
  });

  final String code;
  final String teamId;
  final DateTime expiresAt;

  static const rotateEvery = Duration(seconds: 30);
  static const codeLifetime = Duration(seconds: 45);
}

/// How long a shared invite link keeps working.
enum InviteLinkExpiry {
  hour(Duration(hours: 1), '1 hour'),
  day(Duration(days: 1), '1 day'),
  week(Duration(days: 7), '7 days'),
  month(Duration(days: 30), '30 days');

  const InviteLinkExpiry(this.duration, this.label);

  final Duration duration;
  final String label;

  static const standard = week;
}
