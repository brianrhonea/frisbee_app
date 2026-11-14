import '../utils/invite_links.dart';

/// The legal pages on the website (`apps/web/content`), opened from Settings.
abstract final class LegalLinks {
  static Uri _page(String path) => Uri.https(InviteLinks.host, path);

  static final privacy = _page('/privacy');
  static final cookies = _page('/cookies');
  static final terms = _page('/terms');

  /// How to delete an account and what goes with it; app stores link here.
  static final deleteAccount = _page('/delete-account');
}
