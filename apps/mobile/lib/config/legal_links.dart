import '../utils/invite_links.dart';

/// The legal pages on the website (`apps/web/content`), opened from Settings.
abstract final class LegalLinks {
  static Uri _page(String path) => Uri.https(InviteLinks.host, path);

  static final privacy = _page('/privacy');
  static final terms = _page('/terms');

  /// What's welcome on Stall 10; agreed to when signing up.
  static final guidelines = _page('/guidelines');

  /// How to delete an account and what goes with it; app stores link here.
  static final deleteAccount = _page('/delete-account');
}
