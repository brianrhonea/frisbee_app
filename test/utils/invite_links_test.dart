import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/linkified_text.dart';
import 'package:frisbee_app/utils/invite_links.dart';

void main() {
  test('builds join and group links on the hosting domain', () {
    expect(
      InviteLinks.join('ABC234').toString(),
      'https://frisbee-app-brianrhonea.web.app/join/ABC234',
    );
    expect(
      InviteLinks.group('g1').toString(),
      'https://frisbee-app-brianrhonea.web.app/g/g1',
    );
  });

  test('maps its own links to in-app routes, and nothing else', () {
    String? path(String s) => InviteLinks.inAppPath(Uri.parse(s));
    expect(
      path('https://frisbee-app-brianrhonea.web.app/join/ABC234'),
      '/join/ABC234',
    );
    expect(path('https://frisbee-app-brianrhonea.web.app/g/g1'), '/g/g1');
    expect(path('stall10://open/join/ABC234'), '/join/ABC234');
    // Not ours, or not an invite.
    expect(path('https://example.com/join/ABC234'), isNull);
    expect(path('http://frisbee-app-brianrhonea.web.app/join/ABC234'), isNull);
    expect(path('https://frisbee-app-brianrhonea.web.app/teams/t1'), isNull);
    expect(path('https://frisbee-app-brianrhonea.web.app/join/'), isNull);
  });

  test('finds links in message text, leaving trailing punctuation', () {
    final parts = splitLinks(
      'Join Cascades on Stall 10: https://frisbee-app-brianrhonea.web.app/join/ABC234. '
      'Field map at www.example.com/map!',
    );
    expect(parts.map((p) => p.$1), [
      'Join Cascades on Stall 10: ',
      'https://frisbee-app-brianrhonea.web.app/join/ABC234',
      '. Field map at ',
      'www.example.com/map',
      '!',
    ]);
    expect(parts[1].$2!.path, '/join/ABC234');
    expect(parts[3].$2.toString(), 'https://www.example.com/map');
    expect(splitLinks('no links here').single.$2, isNull);
  });
}
