import 'package:flutter/foundation.dart';

/// Where the "Update required" screen sends people to get the new build.
///
/// Android: the Play listing for the app's id. iOS: the App Store (or, during
/// the TestFlight beta, the TestFlight invitation) link is not known to the
/// code; the owner passes it with
/// `--dart-define=IOS_UPDATE_URL=<link>`. Until then iOS opens the App Store
/// home page.
abstract final class StoreLinks {
  static const _ios = String.fromEnvironment(
    'IOS_UPDATE_URL',
    defaultValue: 'https://apps.apple.com/',
  );

  static final Uri android = Uri.https(
    'play.google.com',
    '/store/apps/details',
    {'id': 'com.brianrhonea.frisbee_app'},
  );

  static final Uri ios = Uri.parse(_ios);

  /// The link for this device.
  static Uri forPlatform([TargetPlatform? platform]) =>
      switch (platform ?? defaultTargetPlatform) {
        TargetPlatform.android => android,
        _ => ios,
      };
}
