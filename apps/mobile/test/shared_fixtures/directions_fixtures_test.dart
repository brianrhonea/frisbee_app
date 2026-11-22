// Shared vectors for "Directions" (lib/domain/models/directions.dart),
// checked by packages/shared/test/directions_fixtures.test.ts against
// directionsOptions in directions.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/calendar.dart';
import 'package:frisbee_app/domain/models/directions.dart';

import 'fixture_file.dart';

void main() {
  test('directions match fixtures/directions/options.json', () {
    final places = <(String, String?, (double, double)?)>[
      ('an address', '1200 Riverside Dr, Denver, CO', null),
      ('a park with symbols', " Wash Park & Field #3 ", null),
      ('a point', null, (39.7, -104.97)),
    ];
    checkFixture(
      'directions/options.json',
      'directionsOptions (directions.dart) for each place and platform.',
      [
        for (final (name, place, point) in places)
          for (final platform in SubscribePlatform.values)
            {
              'name': '$name on ${platform.name}',
              'place': place,
              'point': point == null ? null : [point.$1, point.$2],
              'platform': platform,
              'options': [
                for (final o in directionsOptions(
                  platform,
                  place: place,
                  point: point,
                ))
                  {'app': o.app, 'label': o.label, 'url': o.url.toString()},
              ],
            },
      ],
    );
  });
}
