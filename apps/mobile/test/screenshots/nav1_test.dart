// Sprint 5, NAV1: a frame strip of the chat slide (Chats > team chat list >
// room: push at t=0, 0.5, 1 then pop at t=0, 0.5, 1). Skipped unless asked:
//   flutter test test/screenshots/nav1_test.dart \
//     --dart-define=SCREENSHOTS=<review/app dir>
// Writes <dir>/NAV1/chat_slide_strip.png. Uses the app's real `chatPage` on
// the Android-style transition; iOS uses the native page.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';

import '../testing/chat_transition_app.dart';
import '../ui_harness/harness.dart' show loadAppFonts;
import 's4_common.dart' show s4Out;

const _w = 390.0;
const _h = 600.0;

void main() {
  final skip = s4Out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>' : null;

  testWidgets('chat slide frame strip', (t) async {
    await loadAppFonts(t);
    t.view.physicalSize = const Size(_w, _h);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    final router = chatTransitionRouter();
    addTearDown(router.dispose);
    await t.pumpWidget(
      RepaintBoundary(key: key, child: chatTransitionApp(router)),
    );
    router.push('/list');
    await t.pumpAndSettle();

    final frames = <ui.Image>[];
    Future<void> grab() async {
      await t.runAsync(() async {
        final b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        frames.add(await b.toImage());
      });
    }

    Future<void> run(void Function() action) async {
      action();
      await t.pump();
      await grab(); // t = 0
      await t.pump(AppMotion.pageIn ~/ 2);
      await grab(); // t = 0.5
      await t.pump(AppMotion.pageIn ~/ 2);
      await grab(); // t = 1
      await t.pumpAndSettle();
    }

    await run(() => router.push('/room'));
    await run(router.pop);

    await t.runAsync(() async {
      const gap = 12.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final total = frames.length * (_w + gap) - gap;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, total, _h),
        Paint()..color = const Color(0xFF444444),
      );
      for (var i = 0; i < frames.length; i++) {
        canvas.drawImage(frames[i], Offset(i * (_w + gap), 0), Paint());
      }
      final image = await recorder.endRecording().toImage(
        total.round(),
        _h.round(),
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('$s4Out/NAV1').createSync(recursive: true);
      File(
        '$s4Out/NAV1/chat_slide_strip.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    });
  }, skip: skip != null);
}
