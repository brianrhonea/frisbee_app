import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository_firebase.dart';
import 'package:frisbee_app/data/services/account_service.dart';
import 'package:frisbee_app/data/services/auth_service.dart';
import 'package:frisbee_app/ui/auth/view_models/agree_terms_viewmodel.dart';
import 'package:frisbee_app/ui/auth/view_models/choose_username_viewmodel.dart';
import 'package:frisbee_app/ui/personal/view_models/personal_details_viewmodel.dart';
import 'package:frisbee_app/ui/profile/view_models/profile_viewmodel.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../testing/fakes.dart';

/// M-B1: every sign-out stops this device's pushes for the signed-in uid
/// first. The check sits in the auth repository, so each view model's
/// sign-out is run against the real one.
void main() {
  late MockFirebaseAuth auth;
  late AuthRepositoryFirebase repo;
  late FakeNotificationRepository notifications;
  late List<String> events;

  /// Whether the login still existed when the hook ran.
  late bool signedInDuringHook;
  late Future<void> Function(String uid) hook;

  AuthRepositoryFirebase build({
    Duration timeout = const Duration(seconds: 4),
  }) => AuthRepositoryFirebase(
    authService: AuthService(auth: auth),
    accountService: AccountService(
      projectId: 'demo',
      auth: auth,
      // The account server refuses, so a delete fails.
      client: MockClient((_) async => http.Response('{}', 500)),
    ),
    firestore: FakeFirebaseFirestore(),
    beforeSignOut: (uid) => hook(uid),
    beforeSignOutTimeout: timeout,
  );

  setUp(() async {
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'u1', email: 'pat@example.com'),
    );
    events = [];
    notifications = FakeNotificationRepository();
    signedInDuringHook = false;
    hook = (uid) async {
      signedInDuringHook = auth.currentUser != null;
      events.add('unregister:$uid');
      await notifications.unregisterDevice(uid);
    };
    repo = build();
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => repo.dispose());

  void expectUnregisteredFirst() {
    expect(events, ['unregister:u1']);
    expect(notifications.unregistered, ['u1']);
    expect(signedInDuringHook, isTrue);
    expect(auth.currentUser, isNull);
  }

  test('the repository unregisters, then signs out', () async {
    await repo.signOut();
    expectUnregisteredFirst();
  });

  test('agree terms sign-out', () async {
    final vm = AgreeTermsViewModel(
      agreementRepository: FakeAgreementRepository(agreed: false),
      authRepository: repo,
    );
    await vm.signOut.execute();
    expectUnregisteredFirst();
    vm.dispose();
  });

  test('choose username sign-out', () async {
    final vm = ChooseUsernameViewModel(authRepository: repo);
    await vm.signOut.execute();
    expectUnregisteredFirst();
    vm.dispose();
  });

  test('personal details sign-out', () async {
    final vm = PersonalDetailsViewModel(
      personalRepository: FakePersonalDetailsRepository(),
      authRepository: repo,
    );
    await vm.signOut.execute();
    expectUnregisteredFirst();
    vm.dispose();
  });

  test('personal details: a failed delete signs out through it too', () async {
    final vm = PersonalDetailsViewModel(
      personalRepository: FakePersonalDetailsRepository(),
      authRepository: repo,
      finishing: true,
    );
    await vm.refuseUnderAge();
    expectUnregisteredFirst();
    vm.dispose();
  });

  test('Settings sign-out unregisters once, before signing out', () async {
    final vm = ProfileViewModel(
      authRepository: repo,
      themeRepository: FakeThemeRepository(),
      notificationRepository: notifications,
      directMessageRepository: FakeDirectMessageRepository(),
    );
    await vm.signOut.execute();
    expectUnregisteredFirst();
    vm.dispose();
  });

  test('a hook that throws does not stop sign-out', () async {
    hook = (_) async => throw Exception('boom');
    expect(await repo.signOut(), isA<Ok<void>>());
    expect(auth.currentUser, isNull);
  });

  test(
    'offline: a hook that never finishes times out, then signs out',
    () async {
      hook = (_) => Completer<void>().future;
      repo.dispose();
      repo = build(timeout: const Duration(milliseconds: 50));
      await Future<void>.delayed(Duration.zero);
      expect(await repo.signOut(), isA<Ok<void>>());
      expect(auth.currentUser, isNull);
    },
  );

  test('nobody signed in: no hook, no error', () async {
    await auth.signOut();
    await Future<void>.delayed(Duration.zero);
    expect(await repo.signOut(), isA<Ok<void>>());
    expect(events, isEmpty);
  });
}
