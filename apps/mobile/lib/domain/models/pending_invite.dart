/// Someone invited to a team who hasn't answered yet, as
/// `GET /v1/teams/:teamId/invites` lists them (`PendingInvite` in
/// packages/shared): for whoever may invite people.
class PendingInvite {
  const PendingInvite({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.invitedByName = '',
    this.invitedAt,
  });

  factory PendingInvite.fromJson(Map<String, Object?> json) => PendingInvite(
    uid: json['uid'] as String? ?? '',
    name: json['name'] as String? ?? 'Someone',
    photoUrl: json['photoUrl'] as String?,
    invitedByName: json['invitedByName'] as String? ?? '',
    invitedAt: DateTime.tryParse(json['invitedAt'] as String? ?? '')?.toLocal(),
  );

  final String uid;
  final String name;
  final String? photoUrl;
  final String invitedByName;
  final DateTime? invitedAt;
}
