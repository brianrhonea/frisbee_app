// N11 (app half): every public link in packages/shared/fixtures/
// shared_links.json opens the matching app page. The website reads the same
// file for its half.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/routing/open_link.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/utils/invite_links.dart';
import 'package:go_router/go_router.dart';

import '../testing/app_harness.dart';
import 'link_helpers.dart';

const _file = '../../packages/shared/fixtures/shared_links.json';

List<Map<String, Object?>> _cases() {
  final doc = jsonDecode(File(_file).readAsStringSync()) as Map;
  return [for (final c in doc['cases'] as List) (c as Map).cast()];
}

void main() {
  final cases = _cases();

  test('the fixture is well formed', () {
    expect(cases, isNotEmpty);
    final names = <String>{};
    for (final c in cases) {
      expect(names.add(c['name']! as String), isTrue, reason: 'duplicate name');
      expect((c['path']! as String).startsWith('/'), isTrue);
      expect(linkPages, contains(c['page']), reason: '${c['name']}');
      expect(c['appRoute'], isA<String>());
      expect(c['web'], isA<String>());
    }
  });

  test('links the app builds for sharing are in the fixture', () {
    final paths = {for (final c in cases) c['path']! as String};
    expect(paths, contains(InviteLinks.join('ABC234').path));
    expect(paths, contains(InviteLinks.group('t1').path));
    expect(paths, contains(InviteLinks.post('p1').path));
    expect(paths, contains(InviteLinks.tournament('x1').path));
  });

  for (final c in cases) {
    final name = c['name']! as String;
    final path = c['path']! as String;
    final page = linkPages[c['page']]!;
    final landing = Uri.parse(c['appRoute']! as String);

    testWidgets('$name ($path) opens the app page, as a link', (t) async {
      await pumpFullApp(t);
      final router = GoRouter.of(t.element(find.byType(HomeScreen)));
      router.go(path);
      await t.pumpAndSettle();
      expectFound(t, path);
      expect(find.byType(page), findsOneWidget);
      final here = router.routerDelegate.currentConfiguration.uri;
      expect(here.path, landing.path, reason: 'after any redirect');
      expect(here.queryParameters, landing.queryParameters);
      expect(t.takeException(), isNull);
    });

    testWidgets('$name ($path) opens the app page, from a notification', (
      t,
    ) async {
      await pumpFullApp(t);
      final router = GoRouter.of(t.element(find.byType(HomeScreen)));
      router.openFromOutside(path);
      await t.pumpAndSettle();
      expectFound(t, path);
      expect(find.byType(page), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
