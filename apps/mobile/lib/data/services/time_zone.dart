import 'package:flutter_timezone/flutter_timezone.dart';

/// The device's IANA time zone ("America/Denver"), which the API uses to
/// keep a repeating event's wall-clock time across clock changes. UTC when
/// the platform can't say (tests, unsupported platforms).
Future<String> localTimeZone() async {
  try {
    final tz = (await FlutterTimezone.getLocalTimezone()).identifier;
    return tz.isEmpty ? 'UTC' : tz;
  } catch (_) {
    return 'UTC';
  }
}
