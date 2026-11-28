// Test helpers for the UI rework (docs/specifications/ui-migration-plan.md):
// golden (screenshot) tests at phone, tablet and desktop widths in light and
// dark, accessibility guideline checks, and a large-text overflow check.
//
// Goldens are recorded on Windows, the reference machine. Font rendering
// differs on macOS and Linux, so golden comparisons are skipped elsewhere
// (Codemagic runs `flutter test` on a Mac); the accessibility and
// large-text checks run everywhere. Record or update goldens with:
//   flutter test --update-goldens test/<file>_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';

/// Widths the guide's layouts are checked at (logical pixels).
enum GoldenWidth {
  phone(360),
  tablet(768),
  desktop(1280);

  const GoldenWidth(this.px);
  final double px;
}

enum GoldenTheme { light, dark }

/// Pass as `skip:` on golden tests: they only compare on the reference
/// machine. Null (run) on Windows.
final String? goldenSkip = Platform.isWindows
    ? null
    : 'Goldens are recorded on Windows; font rendering differs here';

bool _fontsLoaded = false;

/// Loads Inter, Barlow Condensed and Material Icons so goldens show real
/// text instead of test boxes. Safe to call more than once.
///
/// Once loaded, the fonts stay for the rest of the test file. expectGoldens
/// calls this, but goldens are skipped off Windows, so a test that depends
/// on real text widths (taps near an edge, overflow checks) must call it
/// itself, or it passes on Windows and fails on the Codemagic Mac.
/// Contrast checks (expectAccessible) are more reliable with the test font:
/// with real glyphs, anti-aliasing on short words like "or" reads as low
/// contrast.
Future<void> loadAppFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    Future<void> family(String name, List<String> files) async {
      final loader = FontLoader(name);
      for (final f in files) {
        final bytes = File(f).readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }

    await family('Inter', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'])
        'assets/fonts/Inter-$w.ttf',
    ]);
    await family('Barlow Condensed', [
      for (final w in ['Bold', 'ExtraBold', 'ExtraBoldItalic'])
        'assets/fonts/BarlowCondensed-$w.ttf',
    ]);
    // The test runs under <flutter>/bin/cache/...; find the SDK's icon font.
    var dir = File(Platform.resolvedExecutable).parent;
    const icons =
        'bin/cache/artifacts/material_fonts/materialicons-regular.otf';
    while (!File('${dir.path}/$icons').existsSync() && dir.parent != dir) {
      dir = dir.parent;
    }
    await family('MaterialIcons', ['${dir.path}/$icons']);
  });
  _fontsLoaded = true;
}

/// Pumps [child] in the app theme at [width] x [height], with optional
/// [textScale].
Future<void> pumpInApp(
  WidgetTester tester,
  Widget child, {
  GoldenTheme theme = GoldenTheme.light,
  double width = 360,
  double height = 640,
  double textScale = 1,
  Key? boundaryKey,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // A new app per theme and size, so the theme doesn't animate from
      // the previous pump into the capture.
      key: ValueKey('${theme.name}-$width-$height-$textScale'),
      debugShowCheckedModeBanner: false,
      theme: theme == GoldenTheme.dark ? AppTheme.dark : AppTheme.light,
      home: MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            // Paint the page colour inside the capture; otherwise the
            // golden shows a transparent background.
            child: Builder(
              builder: (context) => ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SizedBox.expand(child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Compares [child] against `goldens/<name>.<theme>.<width>.png` for every
/// combination of [themes] and [widths].
Future<void> expectGoldens(
  WidgetTester tester,
  Widget child,
  String name, {
  List<GoldenTheme> themes = GoldenTheme.values,
  List<GoldenWidth> widths = const [GoldenWidth.phone],
  double height = 640,
}) async {
  await loadAppFonts(tester);
  for (final theme in themes) {
    for (final width in widths) {
      final key = UniqueKey();
      await pumpInApp(
        tester,
        child,
        theme: theme,
        width: width.px,
        height: height,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile(
          'goldens/$name.${theme.name}.${width.px.toInt()}.png',
        ),
      );
    }
  }
}

/// Checks what's on screen against Flutter's accessibility guidelines:
/// 48 px tap targets (the guide's minimum), labelled tap targets and text
/// contrast.
Future<void> expectAccessible(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

/// Pumps [child] with text at [scale] (200% by default) and fails on any
/// layout overflow.
Future<void> expectNoOverflowWithLargeText(
  WidgetTester tester,
  Widget child, {
  double scale = 2,
  double width = 360,
  double height = 640,
  GoldenTheme theme = GoldenTheme.light,
}) async {
  await pumpInApp(
    tester,
    child,
    theme: theme,
    width: width,
    height: height,
    textScale: scale,
  );
  expect(
    tester.takeException(),
    isNull,
    reason: 'layout overflowed with text at ${(scale * 100).round()}%',
  );
}
