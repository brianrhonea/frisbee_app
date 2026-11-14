import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_in_viewmodel.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_up_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/auth_layout.dart';
import 'package:frisbee_app/ui/auth/widgets/disc_throw_hero.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_in_screen.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_up_screen.dart';

import '../testing/fakes.dart';

void main() {
  setUp(AuthLayout.debugReset);

  Widget signIn({bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 860),
        disableAnimations: reduceMotion,
      ),
      child: SignInScreen(
        viewModel: SignInViewModel(authRepository: FakeAuthRepository()),
      ),
    ),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test('the stall counts 1 to 9 in flight, then 10 on the catch', () {
    expect(DiscThrowTimeline.stall(0), 1);
    expect(DiscThrowTimeline.stall(0.3), inInclusiveRange(2, 9));
    expect(DiscThrowTimeline.stall(0.6), 9);
    expect(DiscThrowTimeline.stall(1), 10);
    var last = 0;
    for (var t = 0.0; t <= 1; t += 0.01) {
      final n = DiscThrowTimeline.stall(t);
      expect(n, greaterThanOrEqualTo(last), reason: 'never counts back');
      last = n;
    }
  });

  testWidgets('the throw counts the stall up to 10, then settles', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(signIn());
    expect(find.textContaining('Stall'), findsOneWidget);
    expect(find.text('Stall 10', findRichText: true), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Stall 10', findRichText: true), findsOneWidget);
    expect(
      find.text('Your team, from the pull to the final point.'),
      findsOneWidget,
    );
    expect(find.text('Good to see you again.'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('tapping the field throws again; the form stays', (tester) async {
    phone(tester);
    await tester.pumpWidget(signIn());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DiscThrowHero));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Stall 10', findRichText: true), findsNothing);
    final form = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Sign in').first,
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(form.opacity, 1);
    await tester.pumpAndSettle();
    expect(find.text('Stall 10', findRichText: true), findsOneWidget);
  });

  testWidgets('plays once per launch', (tester) async {
    phone(tester);
    await tester.pumpWidget(signIn());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(signIn());
    expect(find.text('Stall 10', findRichText: true), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with reduced motion it shows the logo straight away', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(signIn(reduceMotion: true));
    expect(find.text('Stall 10', findRichText: true), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.tap(find.byType(DiscThrowHero));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('wide screens put the field beside the form', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          viewModel: SignInViewModel(authRepository: FakeAuthRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final hero = tester.getRect(find.byType(DiscThrowHero));
    final button = tester.getRect(find.widgetWithText(FilledButton, 'Sign in'));
    expect(hero.right, lessThanOrEqualTo(button.left));
    expect(tester.takeException(), isNull);
  });

  for (final (name, screen) in [
    (
      'sign-in',
      () => SignInScreen(
        viewModel: SignInViewModel(authRepository: FakeAuthRepository()),
      ),
    ),
    (
      'sign-up',
      () => SignUpScreen(
        viewModel: SignUpViewModel(
          authRepository: FakeAuthRepository(),
          personalRepository: FakePersonalDetailsRepository(),
        ),
      ),
    ),
  ]) {
    testWidgets('the whole $name form fits on a big phone without scrolling', (
      tester,
    ) async {
      // iPhone 17 Pro Max, in logical pixels.
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: screen()));
      await tester.pumpAndSettle();

      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.maxScrollExtent, 0);
      expect(
        tester.getSize(find.byType(DiscThrowHero)).height,
        greaterThanOrEqualTo(200),
      );
    });
  }
}
