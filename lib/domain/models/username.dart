/// A user's unique handle, shown as `@name`. Stored lowercase; one account
/// per username, which firestore.rules enforces with `usernames/{name}`.
abstract final class Username {
  static const minLength = 3;
  static const maxLength = 20;

  static final _allowed = RegExp(r'^[a-z0-9_.]+$');

  /// Names that would look official.
  static const _reserved = {
    'admin',
    'administrator',
    'stall10',
    'support',
    'help',
    'team',
    'official',
    'moderator',
    'null',
    'undefined',
  };

  /// [input] as stored: trimmed, without a leading "@", lowercase.
  static String normalize(String input) {
    final t = input.trim().toLowerCase();
    return t.startsWith('@') ? t.substring(1) : t;
  }

  /// What's wrong with [input] as a username, or null when it's fine.
  static String? problem(String input) {
    final name = normalize(input);
    if (name.length < minLength) return 'At least $minLength characters';
    if (name.length > maxLength) return 'At most $maxLength characters';
    if (!_allowed.hasMatch(name)) {
      return 'Use only letters, numbers, _ and .';
    }
    if (name.startsWith('.') || name.endsWith('.') || name.contains('..')) {
      return "Periods can't be first, last or doubled";
    }
    if (_reserved.contains(name)) return 'That username is reserved';
    return null;
  }
}

/// Someone else got the username first.
class UsernameTakenException implements Exception {
  const UsernameTakenException(this.username);
  final String username;

  @override
  String toString() => '@$username is taken. Try another.';
}
