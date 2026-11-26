// #6: the minimum-build gate. View model (fail open, live, resume) and the
// "Update required" screen over the app.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/account_gate/account_gate.dart';
import 'package:frisbee_app/data/repositories/agreement/agreement_repository.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/personal/personal_repository.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/auth/widgets/agree_terms_screen.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/config/store_links.dart';
import 'package:frisbee_app/data/repositories/meta_flags/meta_flags_repository.dart';
import 'package:frisbee_app/domain/models/meta_flags.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/update/view_models/update_gate_viewmodel.dart';
import 'package:frisbee_app/ui/update/widgets/update_gate.dart';
import 'package:frisbee_app/ui/update/widgets/update_required_screen.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

class _FakeFlags implements MetaFlagsRepository {
  MetaFlags? next;
  bool throws = false;
  bool hangs = false;
  var reads = 0;
  final live = StreamController<MetaFlags?>.broadcast();

  @override
  Future<MetaFlags?> read({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    reads++;
    if (hangs) {
      return Completer<MetaFlags?>().future.timeout(
        timeout,
        onTimeout: () => null,
      );
    }
    if (throws) return null;
    return next;
  }

  @override
  Stream<MetaFlags?> watch() => live.stream;
}

MetaFlags _min(int ios, [int android = 0]) =>
    MetaFlags(minBuildIos: ios, minBuildAndroid: android);

UpdateGateViewModel _vm(
  _FakeFlags repo, {
  AppPlatform? platform = AppPlatform.ios,
  int build = 55,
}) => UpdateGateViewModel(
  repository: repo,
  platform: platform,
  build: build,
  timeout: const Duration(milliseconds: 50),
);

void main() {
  group('UpdateGateViewModel', () {
    test('allows a build at or above the minimum', () async {
      final repo = _FakeFlags()..next = _min(55);
      final vm = _vm(repo);
      await vm.start();
      expect(vm.updateRequired, isFalse);
      expect(vm.minBuild, 55);
      vm.dispose();
    });

    test('blocks a build below the minimum, per platform', () async {
      final repo = _FakeFlags()..next = _min(56, 10);
      final ios = _vm(repo);
      await ios.start();
      expect(ios.updateRequired, isTrue);
      final android = _vm(repo, platform: AppPlatform.android);
      await android.start();
      expect(android.updateRequired, isFalse, reason: 'android minimum is 10');
      ios.dispose();
      android.dispose();
    });

    test('0 means no gate', () async {
      final repo = _FakeFlags()..next = MetaFlags.defaults;
      final vm = _vm(repo, build: 1);
      await vm.start();
      expect(vm.updateRequired, isFalse);
      vm.dispose();
    });

    test('fails open: unreadable, missing, slow or failing flags', () async {
      final repo = _FakeFlags()..next = null;
      var vm = _vm(repo);
      await vm.start();
      expect(vm.updateRequired, isFalse, reason: 'no document');
      vm.dispose();

      repo.throws = true;
      vm = _vm(repo);
      await vm.start();
      expect(vm.updateRequired, isFalse, reason: 'read failed');
      vm.dispose();

      repo
        ..throws = false
        ..hangs = true;
      vm = _vm(repo);
      await vm.start();
      expect(vm.updateRequired, isFalse, reason: 'timed out');
      vm.dispose();
    });

    test(
      'a platform with no gate is never blocked and reads nothing',
      () async {
        final repo = _FakeFlags()..next = _min(999);
        final vm = _vm(repo, platform: null);
        await vm.start();
        expect(vm.updateRequired, isFalse);
        expect(repo.reads, 0);
        vm.dispose();
      },
    );

    test('follows the document live, both ways', () async {
      final repo = _FakeFlags()..next = _min(0);
      final vm = _vm(repo);
      await vm.start();
      var told = 0;
      vm.addListener(() => told++);
      expect(vm.updateRequired, isFalse);
      repo.live.add(_min(60));
      await pumpEventQueue();
      expect(vm.updateRequired, isTrue);
      expect(told, 1);
      repo.live.add(_min(0));
      await pumpEventQueue();
      expect(vm.updateRequired, isFalse, reason: 'the owner lifted the gate');
      vm.dispose();
    });

    test('a failed later read keeps the last good answer', () async {
      final repo = _FakeFlags()..next = _min(60);
      final vm = _vm(repo);
      await vm.start();
      expect(vm.updateRequired, isTrue);
      repo.live.add(null);
      await pumpEventQueue();
      expect(vm.updateRequired, isTrue, reason: 'an outage must not flip it');
      repo.throws = true;
      await vm.recheck();
      expect(vm.updateRequired, isTrue);
      vm.dispose();
    });

    test('recheck (app resumed) picks up a change', () async {
      final repo = _FakeFlags()..next = _min(0);
      final vm = _vm(repo);
      await vm.start();
      expect(vm.updateRequired, isFalse);
      repo.next = _min(70);
      await vm.recheck();
      expect(vm.updateRequired, isTrue);
      vm.dispose();
    });

    test('start does not wait for a slow read to finish the app start', () {
      final repo = _FakeFlags()..hangs = true;
      final vm = _vm(repo);
      // Not awaited: that is how main() calls it.
      final started = vm.start();
      expect(vm.updateRequired, isFalse, reason: 'allowed until it answers');
      return started.then((_) => vm.dispose());
    });
  });

  group('UpdateGate', () {
    Widget app(UpdateGateViewModel vm, {Future<bool> Function(Uri)? open}) =>
        MaterialApp(
          theme: AppTheme.light,
          builder: (_, child) => UpdateGate(
            viewModel: vm,
            open: open ?? (_) async => true,
            child: child!,
          ),
          home: const Scaffold(body: Center(child: Text('The app'))),
        );

    testWidgets('shows the app when the build is allowed', (t) async {
      final vm = _vm(_FakeFlags()..next = _min(0));
      await t.runAsync(vm.start);
      await t.pumpWidget(app(vm));
      expect(find.text('The app'), findsOneWidget);
      expect(find.byType(UpdateRequiredScreen), findsNothing);
      vm.dispose();
    });

    testWidgets('covers the app with the update screen when too old', (
      t,
    ) async {
      final vm = _vm(_FakeFlags()..next = _min(90));
      await t.runAsync(vm.start);
      await t.pumpWidget(app(vm));
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Update the app'), findsOneWidget);
      expect(find.text('The app'), findsNothing, reason: 'not reachable');
      vm.dispose();
    });

    testWidgets('Update opens the store link for this platform', (t) async {
      final vm = _vm(_FakeFlags()..next = _min(90));
      await t.runAsync(vm.start);
      final opened = <Uri>[];
      await t.pumpWidget(
        app(
          vm,
          open: (u) async {
            opened.add(u);
            return true;
          },
        ),
      );
      await t.tap(find.text('Update the app'));
      await t.pump();
      expect(opened, [StoreLinks.forPlatform()]);
      vm.dispose();
    });

    testWidgets('appears live, and goes when the gate is lifted, keeping the '
        'app\'s state', (t) async {
      final repo = _FakeFlags()..next = _min(0);
      final vm = _vm(repo);
      await t.runAsync(vm.start);
      final field = TextEditingController(text: 'draft');
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (_, child) => UpdateGate(viewModel: vm, child: child!),
          home: Scaffold(body: TextField(controller: field)),
        ),
      );
      expect(find.byType(UpdateRequiredScreen), findsNothing);
      await t.runAsync(() async {
        repo.live.add(_min(90));
        await pumpEventQueue();
      });
      await t.pump();
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
      await t.runAsync(() async {
        repo.live.add(_min(0));
        await pumpEventQueue();
      });
      await t.pump();
      expect(find.byType(UpdateRequiredScreen), findsNothing);
      expect(find.text('draft'), findsOneWidget, reason: 'state kept');
      vm.dispose();
    });

    testWidgets('re-checks when the app resumes', (t) async {
      final repo = _FakeFlags()..next = _min(0);
      final vm = _vm(repo);
      await t.runAsync(vm.start);
      await t.pumpWidget(app(vm));
      final before = repo.reads;
      repo.next = _min(90);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.runAsync(pumpEventQueue);
      await t.pump();
      expect(repo.reads, greaterThan(before));
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
      vm.dispose();
    });

    testWidgets('the back button does not dismiss the update screen', (
      t,
    ) async {
      final vm = _vm(_FakeFlags()..next = _min(90));
      await t.runAsync(vm.start);
      await t.pumpWidget(app(vm));
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
      vm.dispose();
    });
  });

  group('UpdateGate over the real router with an account-gate redirect', () {
    testWidgets('the update screen wins, and the redirect works once it is '
        'lifted', (t) async {
      final repo = _FakeFlags()..next = _min(90);
      final vm = _vm(repo);
      await t.runAsync(vm.start);
      final auth = FakeAuthRepository(user: testUser);
      final personal = FakePersonalDetailsRepository();
      final agreement = FakeAgreementRepository();
      final gate = AccountGate(auth: auth)..report(['terms']);
      final appRouter = router(auth, personal, agreement, gate: gate);
      addTearDown(appRouter.dispose);
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            ChangeNotifierProvider<PersonalDetailsRepository>.value(
              value: personal,
            ),
            ChangeNotifierProvider<AgreementRepository>.value(value: agreement),
            ChangeNotifierProvider<AccountGate>.value(value: gate),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: appRouter,
            builder: (_, child) => UpdateGate(viewModel: vm, child: child!),
          ),
        ),
      );
      await t.pumpAndSettle();

      // The gate sent the router to the Terms step, but the update screen
      // covers it: nothing underneath is reachable.
      expect(
        appRouter.routeInformationProvider.value.uri.path,
        Routes.agreeTerms,
        reason: 'the redirect ran underneath',
      );
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
      expect(find.byType(AgreeTermsScreen), findsNothing);

      await t.runAsync(() async {
        repo.live.add(_min(0));
        await pumpEventQueue();
      });
      await t.pumpAndSettle();
      expect(find.byType(UpdateRequiredScreen), findsNothing);
      expect(find.byType(AgreeTermsScreen), findsOneWidget);
      vm.dispose();
    });
  });

  group('UpdateRequiredScreen', () {
    Widget screen() => UpdateRequiredScreen(onUpdate: () {});

    testWidgets('goldens, light and dark', skip: goldenSkip != null, (t) async {
      await expectGoldens(t, screen(), 'update_required', height: 640);
    });

    for (final theme in GoldenTheme.values) {
      testWidgets('meets tap target, label and contrast guidelines, '
          '${theme.name}', (t) async {
        await pumpInApp(t, screen(), theme: theme);
        await expectAccessible(t);
      });
    }

    testWidgets('fits at text scale 2.0', (t) async {
      await expectNoOverflowWithLargeText(t, screen(), height: 640);
      await expectNoOverflowWithLargeText(
        t,
        screen(),
        width: 320,
        height: 480,
        theme: GoldenTheme.dark,
      );
    });

    testWidgets('has a heading and one button', (t) async {
      final h = t.ensureSemantics();
      await pumpInApp(t, screen());
      expect(find.text('Update required'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      h.dispose();
    });
  });

  group('StoreLinks', () {
    test('Android opens the Play listing of the app id', () {
      expect(
        StoreLinks.forPlatform(TargetPlatform.android).toString(),
        'https://play.google.com/store/apps/details?id=com.brianrhonea.frisbee_app',
      );
    });

    test('iOS opens the configured App Store / TestFlight link', () {
      expect(StoreLinks.forPlatform(TargetPlatform.iOS).scheme, 'https');
    });
  });
}
