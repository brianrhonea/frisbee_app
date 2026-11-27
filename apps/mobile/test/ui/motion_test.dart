// N13: navigation motion follows AppMotion (K7): fast 120, base 200,
// sheet 300, easing (0.2, 0, 0, 1), and nothing moves when animations are
// off.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_layout.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/confirm_dialog.dart';
import 'package:frisbee_app/ui/core/ui/slide_over_page.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:go_router/go_router.dart';

import '../testing/app_harness.dart';

/// Builds [body] with a [BuildContext] under a MediaQuery that has
/// animations [off] or on.
Future<BuildContext> _context(WidgetTester t, {required bool off}) async {
  late BuildContext ctx;
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: off),
        child: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return ctx;
}

CustomTransitionPage<void> _asCustom(Page<void> p) =>
    p as CustomTransitionPage<void>;

void main() {
  test('the tokens: 120, 200, 300 and (0.2, 0, 0, 1)', () {
    expect(AppMotion.fast, const Duration(milliseconds: 120));
    expect(AppMotion.base, const Duration(milliseconds: 200));
    expect(AppMotion.sheet, const Duration(milliseconds: 300));
    expect(AppMotion.easing, const Cubic(0.2, 0, 0, 1));
    expect(AppMotion.pageIn, AppMotion.base);
    expect(AppMotion.pageOut, AppMotion.base);
  });

  group('sheet and dialog styles', () {
    testWidgets('sheets: 300 in, 200 out, on the easing', (t) async {
      final style = AppMotion.sheetStyle(await _context(t, off: false));
      expect(style.duration, AppMotion.sheet);
      expect(style.reverseDuration, AppMotion.base);
      expect(style.curve, AppMotion.easing);
      expect(style.reverseCurve, AppMotion.easing);
    });

    testWidgets('dialogs: fast both ways on the easing', (t) async {
      final style = AppMotion.dialogStyle(await _context(t, off: false));
      expect(style.duration, AppMotion.fast);
      expect(style.reverseDuration, AppMotion.fast);
      expect(style.curve, AppMotion.easing);
    });

    testWidgets('reduced motion turns both off', (t) async {
      final ctx = await _context(t, off: true);
      expect(AppMotion.sheetStyle(ctx), AnimationStyle.noAnimation);
      expect(AppMotion.dialogStyle(ctx), AnimationStyle.noAnimation);
    });
  });

  group('slide-over pages', () {
    testWidgets('push and back both take 200 ms', (t) async {
      final ctx = await _context(t, off: false);
      final page = _asCustom(
        slideOverPage(ctx, const ValueKey('p'), const SizedBox()),
      );
      expect(page.transitionDuration, AppMotion.pageIn);
      expect(page.reverseTransitionDuration, AppMotion.pageOut);
    });

    testWidgets('reduced motion: zero duration and no slide', (t) async {
      final ctx = await _context(t, off: true);
      final page = _asCustom(
        slideOverPage(ctx, const ValueKey('p'), const Text('x')),
      );
      expect(page.transitionDuration, Duration.zero);
      expect(page.reverseTransitionDuration, Duration.zero);
      final child = const Text('x');
      expect(
        page.transitionsBuilder(
          ctx,
          const AlwaysStoppedAnimation(0.5),
          const AlwaysStoppedAnimation(0),
          child,
        ),
        same(child),
      );
    });

    testWidgets('the slide follows the easing curve', (t) async {
      final ctx = await _context(t, off: false);
      final page = _asCustom(
        slideOverPage(ctx, const ValueKey('p'), const SizedBox()),
      );
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: page.transitionsBuilder(
            ctx,
            const AlwaysStoppedAnimation(0.5),
            const AlwaysStoppedAnimation(0),
            const SizedBox(),
          ),
        ),
      );
      final slide = t.widget<SlideTransition>(find.byType(SlideTransition));
      expect(
        slide.position.value.dx,
        closeTo(1 - AppMotion.easing.transform(0.5), 1e-9),
      );
    });
  });

  group('chat pages', () {
    testWidgets('200 both ways; reduced motion shows the page at once', (
      t,
    ) async {
      final on = await _context(t, off: false);
      final timed = _asCustom(
        chatPage(on, const ValueKey('c'), const SizedBox()),
      );
      expect(timed.transitionDuration, AppMotion.base);
      expect(timed.reverseTransitionDuration, AppMotion.base);
      final ctx = await _context(t, off: true);
      final page = _asCustom(
        chatPage(ctx, const ValueKey('c'), const SizedBox()),
      );
      expect(page.transitionDuration, Duration.zero);
      final child = const Text('chat');
      expect(
        page.transitionsBuilder(
          ctx,
          const AlwaysStoppedAnimation(0.5),
          const AlwaysStoppedAnimation(0),
          child,
        ),
        same(child),
      );
    });
  });

  group('page transitions on plain routes', () {
    testWidgets('reduced motion: the page is returned as is', (t) async {
      final ctx = await _context(t, off: true);
      const child = Text('page');
      final route = PageRouteBuilder<void>(pageBuilder: (_, _, _) => child);
      const builder = AppPageTransitionsBuilder(
        FadeUpwardsPageTransitionsBuilder(),
      );
      expect(
        builder.buildTransitions<void>(
          route,
          ctx,
          const AlwaysStoppedAnimation(0.5),
          const AlwaysStoppedAnimation(0),
          child,
        ),
        same(child),
      );
    });

    testWidgets('normal motion: the platform transition runs', (t) async {
      final ctx = await _context(t, off: false);
      const child = Text('page');
      final route = PageRouteBuilder<void>(pageBuilder: (_, _, _) => child);
      const builder = AppPageTransitionsBuilder(
        FadeUpwardsPageTransitionsBuilder(),
      );
      expect(
        builder.buildTransitions<void>(
          route,
          ctx,
          const AlwaysStoppedAnimation(0.5),
          const AlwaysStoppedAnimation(0),
          child,
        ),
        isNot(same(child)),
      );
    });

    test('the theme uses it everywhere but iOS and macOS', () {
      final b = AppTheme.light.pageTransitionsTheme.builders;
      expect(b[TargetPlatform.android], isA<AppPageTransitionsBuilder>());
      expect(b[TargetPlatform.windows], isA<AppPageTransitionsBuilder>());
      expect(b[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
      expect(b[TargetPlatform.macOS], isA<CupertinoPageTransitionsBuilder>());
    });
  });

  group('on the real router', () {
    testWidgets('switching tabs does not slide or fade the page', (t) async {
      await pumpFullApp(t);
      await t.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Teams'),
        ),
      );
      await t.pump();
      // One frame later the page is already in place: no transition.
      expect(find.byType(TeamsScreen), findsOneWidget);
      expect(t.getTopLeft(find.byType(TeamsScreen)).dx, 0);
    });

    testWidgets('a pushed page slides in once, from the right, and settles', (
      t,
    ) async {
      await pumpFullApp(t);
      final router = GoRouter.of(t.element(find.byType(NavigationBar)));
      router.push('/settings');
      // The route is added after the router's async redirect check.
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final mid = t.getTopLeft(find.byType(Scaffold).last).dx;
      expect(mid, greaterThan(0), reason: 'still sliding at 100 ms');
      await t.pump(AppMotion.pageIn);
      await t.pump(AppMotion.pageIn);
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byType(Scaffold).last).dx, lessThan(mid));
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('a pushed page just appears when animations are off', (
      t,
    ) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpFullApp(t);
      final router = GoRouter.of(t.element(find.byType(NavigationBar)));
      router.push('/settings');
      await t.pump();
      await t.pump();
      expect(find.text('Settings'), findsWidgets);
      final left = t.getTopLeft(find.byType(Scaffold).last).dx;
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byType(Scaffold).last).dx, left);
    });
  });

  group('sheets and dialogs run for their token durations', () {
    Future<void> openDialog(WidgetTester t, {required bool off}) async {
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: off),
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    confirmDialog(context, title: 'T', message: 'M'),
                child: const Text('Ask'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Ask'));
    }

    testWidgets('a dialog is done within 120 ms', (t) async {
      await openDialog(t, off: false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(t.hasRunningAnimations, isTrue);
      await t.pump(AppMotion.fast);
      expect(find.text('T'), findsOneWidget);
    });

    testWidgets('a dialog appears at once with animations off', (t) async {
      await openDialog(t, off: true);
      await t.pump();
      await t.pump();
      expect(find.text('T'), findsOneWidget);
    });

    testWidgets('a bottom sheet opens over 300 ms', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                sheetAnimationStyle: AppMotion.sheetStyle(context),
                builder: (_) => const SizedBox(height: 100, child: Text('S')),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 150));
      final at150 = t.getTopLeft(find.text('S')).dy;
      await t.pump(const Duration(milliseconds: 130));
      final at280 = t.getTopLeft(find.text('S')).dy;
      await t.pump(const Duration(milliseconds: 60));
      final at340 = t.getTopLeft(find.text('S')).dy;
      await t.pumpAndSettle();
      final end = t.getTopLeft(find.text('S')).dy;
      expect(at150, greaterThan(end), reason: 'still rising at 150 ms');
      expect(at280, greaterThan(end), reason: 'still rising at 280 ms');
      expect(at340, end, reason: 'in place by 340 ms');
    });
  });
}
