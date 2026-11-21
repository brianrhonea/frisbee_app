import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/calendar.dart';

/// The one "Subscribe" button's options; packages/shared's
/// subscribe_options.test.ts has the same tests.
void main() {
  const feed = (
    url: 'https://api.stall10.app/v1/ical/tok.ics',
    webcal: 'webcal://api.stall10.app/v1/ical/tok.ics',
  );
  List<SubscribeTarget> targets(
    SubscribePlatform p, [
    Set<SubscribeTarget> installed = const {},
  ]) => [
    for (final o in subscribeOptions(feed, p, installed: installed)) o.target,
  ];
  const s = SubscribeTarget.values;

  test('Apple Calendar first on Apple devices, and only there', () {
    expect(targets(SubscribePlatform.ios), [s[0], s[1], s[2], s[3]]);
    expect(targets(SubscribePlatform.macos).first, SubscribeTarget.apple);
    expect(targets(SubscribePlatform.android), isNot(contains(s[0])));
    expect(targets(SubscribePlatform.other), isNot(contains(s[0])));
  });

  test('Google first on Android, Outlook first elsewhere', () {
    expect(targets(SubscribePlatform.android), [s[1], s[2], s[3], s[4]]);
    expect(targets(SubscribePlatform.other), [s[2], s[3], s[1], s[4]]);
  });

  test('installed apps first', () {
    expect(targets(SubscribePlatform.android, {SubscribeTarget.outlook}), [
      s[2],
      s[1],
      s[3],
      s[4],
    ]);
  });

  test('builds each link', () {
    final by = {
      for (final o in subscribeOptions(feed, SubscribePlatform.other))
        o.target: o.url,
    };
    expect(
      by[SubscribeTarget.google],
      'https://calendar.google.com/calendar/r?cid=${Uri.encodeComponent(feed.webcal)}',
    );
    expect(
      by[SubscribeTarget.outlook],
      'https://outlook.live.com/calendar/0/addfromweb?url=${Uri.encodeComponent(feed.url)}&name=Stall%2010',
    );
    expect(
      by[SubscribeTarget.outlookWork],
      startsWith('https://outlook.office.com/calendar/0/addfromweb?url='),
    );
    expect(by[SubscribeTarget.other], feed.webcal);
  });
}
