/// Links that open Stall 10, for sharing in any app (Messages, WhatsApp,
/// email). `/join/<code>` joins a team with its invite code; `/g/<id>`
/// opens a community group's page; `/p/<id>` opens a person's post.
///
/// Firebase Hosting serves them (see `hosting/`): with the app installed,
/// iOS and Android open it straight away; otherwise the page shows the code
/// and an Open in Stall 10 button that uses the [scheme].
abstract final class InviteLinks {
  static const host = 'frisbee-app-brianrhonea.web.app';

  /// The app's own URL scheme, e.g. `stall10://open/join/ABC234`. The host
  /// part is ignored; the path is the in-app route.
  static const scheme = 'stall10';

  static Uri join(String code) =>
      Uri.https(host, '/join/${Uri.encodeComponent(code)}');

  static Uri group(String groupId) =>
      Uri.https(host, '/g/${Uri.encodeComponent(groupId)}');

  static Uri post(String postId) =>
      Uri.https(host, '/p/${Uri.encodeComponent(postId)}');

  /// The in-app route for [uri] if it's one of these links, else null.
  static String? inAppPath(Uri uri) {
    final ours =
        (uri.scheme == 'https' && uri.host == host) || uri.scheme == scheme;
    if (!ours) return null;
    final s = uri.pathSegments;
    if (s.length == 2 && (s[0] == 'join' || s[0] == 'g') && s[1].isNotEmpty) {
      return '/${s[0]}/${Uri.encodeComponent(s[1])}';
    }
    if (s.length == 2 && s[0] == 'p' && s[1].isNotEmpty) {
      return '/posts/${Uri.encodeComponent(s[1])}';
    }
    return null;
  }
}
