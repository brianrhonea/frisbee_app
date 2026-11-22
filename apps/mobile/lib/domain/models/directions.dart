// "Directions" to an event's place: the maps apps to choose from. Each is
// a web link the app opens when it's installed (universal / app links) and
// the browser otherwise, so nothing needs to know what's installed. The
// port of packages/shared/src/directions.ts (the website's); both are
// checked against packages/shared/fixtures/directions.
import 'calendar.dart' show SubscribePlatform;

enum MapsApp {
  apple('Apple Maps'),
  google('Google Maps'),
  waze('Waze');

  const MapsApp(this.label);
  final String label;
}

typedef DirectionsOption = ({MapsApp app, String label, Uri url});

/// The maps apps for directions to [place] (an address or name) or
/// [point] (lat, lng), best first for [platform]: Apple Maps only on Apple
/// devices (first there), then Google Maps and Waze.
List<DirectionsOption> directionsOptions(
  SubscribePlatform platform, {
  String? place,
  (double, double)? point,
}) {
  assert(place != null || point != null);
  final at = point == null ? null : '${point.$1},${point.$2}';
  final q = Uri.encodeComponent(at ?? place!.trim());
  Uri url(MapsApp a) => Uri.parse(switch (a) {
    MapsApp.apple => 'https://maps.apple.com/?daddr=$q',
    MapsApp.google => 'https://www.google.com/maps/dir/?api=1&destination=$q',
    MapsApp.waze =>
      at != null
          ? 'https://waze.com/ul?ll=$q&navigate=yes'
          : 'https://waze.com/ul?q=$q&navigate=yes',
  });
  final order = switch (platform) {
    SubscribePlatform.ios || SubscribePlatform.macos => MapsApp.values,
    _ => [MapsApp.google, MapsApp.waze],
  };
  return [for (final a in order) (app: a, label: a.label, url: url(a))];
}
