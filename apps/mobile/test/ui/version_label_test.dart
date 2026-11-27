// The hidden "Send test crash" at the foot of Settings: staff and debug
// builds only.
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/moderation/moderation_repository.dart';
import 'package:frisbee_app/data/services/crash_reporting.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/settings/widgets/version_label.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../testing/moderation_fakes.dart';

class _Reporter implements CrashReporter {
  int crashes = 0;
  @override
  Future<void> setCollectionEnabled(bool enabled) async {}
  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {}
  @override
  Future<void> recordError(
    Object error,
    StackTrace stack, {
    bool fatal = true,
  }) async {}
  @override
  void crash() => crashes++;
}

void main() {
  late _Reporter reporter;
  late FlutterExceptionHandler? savedHandler;
  late ErrorCallback? savedDispatcher;

  setUp(() async {
    savedHandler = FlutterError.onError;
    savedDispatcher = PlatformDispatcher.instance.onError;
    reporter = _Reporter();
    await CrashReporting.init(
      () => reporter,
      debug: true,
      dispatcher: PlatformDispatcher.instance,
    );
  });

  tearDown(() {
    FlutterError.onError = savedHandler;
    PlatformDispatcher.instance.onError = savedDispatcher;
    CrashReporting.reset();
  });

  Future<void> pump(
    WidgetTester t, {
    required bool staff,
    bool debug = false,
  }) async {
    final moderation = FakeModerationRepository();
    if (staff) moderation.staff.add(testUser.uid);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(
            value: FakeAuthRepository(user: testUser),
          ),
          ChangeNotifierProvider<ModerationRepository>.value(value: moderation),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(child: VersionLabel(debug: debug)),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('staff can long-press to send a test crash, after confirming', (
    t,
  ) async {
    await pump(t, staff: true);
    await t.longPress(find.textContaining(' v'));
    await t.pumpAndSettle();
    expect(find.text('Send test crash?'), findsOneWidget);
    expect(reporter.crashes, 0, reason: 'not before they confirm');
    await t.tap(find.text('Send test crash'));
    await t.pumpAndSettle();
    expect(reporter.crashes, 1);
  });

  testWidgets('cancelling sends nothing', (t) async {
    await pump(t, staff: true);
    await t.longPress(find.textContaining(' v'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(reporter.crashes, 0);
  });

  testWidgets('everyone else in a release build sees nothing to press', (
    t,
  ) async {
    await pump(t, staff: false);
    await t.longPress(find.textContaining(' v'));
    await t.pumpAndSettle();
    expect(find.text('Send test crash?'), findsNothing);
    expect(reporter.crashes, 0);
  });

  testWidgets('a debug build offers it to anyone', (t) async {
    await pump(t, staff: false, debug: true);
    await t.longPress(find.textContaining(' v'));
    await t.pumpAndSettle();
    expect(find.text('Send test crash?'), findsOneWidget);
  });
}
