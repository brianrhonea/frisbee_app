/// A person's first and last name, as sign-up and "Your name and
/// username" ask them. Ports `personNameLimits`, `splitDisplayName`,
/// `joinPersonName`, `asksForName` and `nameMissing` in
/// packages/shared/src/profile.ts (checked by fixtures/profile_names.json).
abstract final class PersonName {
  /// Each box's limit; together, with a space, they fit the profile name.
  static const maxFirst = 30;
  static const maxLast = 30;

  /// [name] (Google's or Apple's, or the profile's) split to start the
  /// name boxes from: the first word, then the rest, each cut to its
  /// limit. Nothing for an empty name or one that looks like an email.
  static ({String first, String last}) split(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty || t.contains('@')) return (first: '', last: '');
    final words = t.split(RegExp(r'\s+'));
    return (
      first: _cut(words.first, maxFirst),
      last: _cut(words.skip(1).join(' '), maxLast),
    );
  }

  /// "Pat Lee": the name everyone sees, from the two boxes.
  static String join(String first, String last) =>
      '${first.trim()} ${last.trim()}'.trim();

  /// No usable name on the account: empty, or an email.
  static bool missing(String? displayName) => split(displayName).first.isEmpty;

  /// Whether the username step asks for their name too: they signed in
  /// with Google or Apple (no password), whose name nobody typed, or the
  /// account has no usable name (Apple can hide it).
  static bool asks(String? displayName, {required bool hasPassword}) =>
      !hasPassword || missing(displayName);

  static String _cut(String s, int max) =>
      (s.length > max ? s.substring(0, max) : s).trim();
}
