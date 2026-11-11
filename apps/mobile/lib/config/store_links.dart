/// Where to download the apps. Shown on the website (lib/ui/web) and, with
/// the same URLs, on the landing page (hosting/index.html).
///
/// TODO: real store URLs once the listings are live. Keep hosting/index.html
/// and hosting/join.html in step.
abstract final class StoreLinks {
  static const appStore = 'https://apps.apple.com/';
  static const playStore = 'https://play.google.com/store/apps';

  /// False until the URLs above point at the real listings; the buttons
  /// then say "Coming soon".
  static const live = false;
}
