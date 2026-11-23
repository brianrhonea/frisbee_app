/// The signed-in user.
class AppUser {
  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.username,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  /// Unique handle, without the "@"; null until chosen (or loaded).
  final String? username;

  AppUser withUsername(String? username) => AppUser(
    uid: uid,
    email: email,
    displayName: displayName,
    photoUrl: photoUrl,
    username: username,
  );

  AppUser withPhotoUrl(String? photoUrl) => AppUser(
    uid: uid,
    email: email,
    displayName: displayName,
    photoUrl: photoUrl,
    username: username,
  );

  /// The name written for this user where others see it (teams, chats,
  /// posts, follows): their name, or "Player". Never their email (pentest
  /// P6; callerLabel in apps/api/src/auth.ts).
  String get label {
    final name = displayName?.trim() ?? '';
    return name.isNotEmpty && !_emailLike.hasMatch(name) ? name : 'Player';
  }

  static final _emailLike = RegExp(r'\S@\S+\.\S');

  /// The name others see on their profile: never the email.
  String get publicName => (displayName?.trim().isNotEmpty ?? false)
      ? displayName!.trim()
      : ((username?.isNotEmpty ?? false) ? username! : 'Player');

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.uid == uid &&
      other.email == email &&
      other.displayName == displayName &&
      other.photoUrl == photoUrl &&
      other.username == username;

  @override
  int get hashCode => Object.hash(uid, email, displayName, photoUrl, username);
}

/// How a user signs in.
enum SignInMethod { password, google, apple }
