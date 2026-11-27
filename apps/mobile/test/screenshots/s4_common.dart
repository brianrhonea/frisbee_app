// Shared by the Sprint 4 screenshot generators (s4_before_test.dart,
// s4_after_test.dart): fonts, the capture and a phone-sized app wrapper.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';

import 'shot_env.dart';

const s4Out = String.fromEnvironment('SCREENSHOTS');
const s4Dark = String.fromEnvironment('SHOT_THEME') == 'dark';

Future<void> _family(String name, List<String> files) async {
  final loader = FontLoader(name);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> loadShotFonts() async {
  await _family('Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'])
      'assets/fonts/Inter-$w.ttf',
  ]);
  await _family('Barlow Condensed', [
    for (final w in ['Bold', 'ExtraBold', 'ExtraBoldItalic'])
      'assets/fonts/BarlowCondensed-$w.ttf',
  ]);
  var dir = File(Platform.resolvedExecutable).parent;
  const icons = 'bin/cache/artifacts/material_fonts/materialicons-regular.otf';
  while (!File('${dir.path}/$icons').existsSync() && dir.parent != dir) {
    dir = dir.parent;
  }
  await _family('MaterialIcons', ['${dir.path}/$icons']);
}

final shotKey = GlobalKey();

/// Phone-sized view at 3x, with the fonts loaded.
Future<void> shotSize(WidgetTester tester) async {
  await tester.runAsync(loadShotFonts);
  tester.view.physicalSize = Size(shotWidth * 3.0, shotHeight * 3.0);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Shows [child] (under [wrap], e.g. providers) in the themed app.
Future<void> shotPump(
  WidgetTester tester,
  Widget child, {
  Widget Function(Widget)? wrap,
}) async {
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: s4Dark ? ThemeMode.dark : ThemeMode.light,
    home: child,
  );
  await tester.pumpWidget(
    RepaintBoundary(key: shotKey, child: wrap == null ? app : wrap(app)),
  );
  await tester.pumpAndSettle();
}

Future<void> shotCapture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump();
  final boundary =
      shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(s4Out).createSync(recursive: true);
    File('$s4Out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}
