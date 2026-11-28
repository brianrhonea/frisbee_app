// NAV1: the chat pages use one Discord-style slide: the new page comes in
// from the right while the page under it shifts left, back reverses it, and
// reduce-motion removes the slide. (iOS and macOS use the native page, which
// drags back with the finger; see the physical-device checks.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:go_router/go_router.dart';

import '../testing/chat_transition_app.dart';

const _width = 800.0;

double _x(WidgetTester t, Key key) => t.getTopLeft(find.byKey(key)).dx;

Future<GoRouter> _pump(WidgetTester t, {bool reduceMotion = false}) async {
  t.view.physicalSize = const Size(_width, 600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final router = chatTransitionRouter();
  addTearDown(router.dispose);
  await t.pumpWidget(chatTransitionApp(router, reduceMotion: reduceMotion));
  return router;
}

void main() {
  testWidgets('a chat page slides in from the right and back out', (t) async {
    final router = await _pump(t);
    router.push('/room');
    await t.pump();
    await t.pump(AppMotion.pageIn ~/ 2);
    final mid = _x(t, roomKey);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(_width));
    await t.pumpAndSettle();
    expect(_x(t, roomKey), 0);

    router.pop();
    await t.pump();
    await t.pump(AppMotion.pageOut ~/ 2);
    final back = _x(t, roomKey);
    expect(back, greaterThan(0));
    expect(back, lessThan(_width));
    await t.pumpAndSettle();
    expect(find.byKey(roomKey), findsNothing);
  });

  testWidgets('the chat list shifts left under the room, and returns', (
    t,
  ) async {
    final router = await _pump(t);
    router.push('/list');
    await t.pumpAndSettle();
    expect(_x(t, listKey), 0);

    router.push('/room');
    await t.pump();
    await t.pump(AppMotion.pageIn ~/ 2);
    // The list is mid-shift to the left (not found offstage once covered,
    // so look at it while the room is still arriving).
    final shifted = _x(t, listKey);
    expect(shifted, lessThan(0));
    expect(shifted, greaterThan(-_width));
    await t.pumpAndSettle();

    router.pop();
    await t.pump();
    await t.pump(AppMotion.pageOut ~/ 2);
    expect(_x(t, listKey), lessThan(0));
    await t.pumpAndSettle();
    expect(_x(t, listKey), 0);
  });

  testWidgets('reduce motion: the page is in place at once, no slide', (
    t,
  ) async {
    final router = await _pump(t, reduceMotion: true);
    router.push('/list');
    await t.pump();
    await t.pump(const Duration(milliseconds: 1));
    expect(_x(t, listKey), 0);
    router.push('/room');
    await t.pump();
    await t.pump(const Duration(milliseconds: 1));
    expect(_x(t, roomKey), 0);
    router.pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 1));
    expect(find.byKey(roomKey), findsNothing);
    expect(_x(t, listKey), 0);
  });

  testWidgets('the slide takes the page-transition token (200 ms)', (t) async {
    final router = await _pump(t);
    router.push('/room');
    await t.pump();
    await t.pump(AppMotion.pageIn - const Duration(milliseconds: 20));
    expect(_x(t, roomKey), greaterThan(0));
    await t.pump(const Duration(milliseconds: 25));
    expect(_x(t, roomKey), 0);
  });
}
