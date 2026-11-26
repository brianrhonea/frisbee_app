import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/account_gate/account_gate.dart';
import 'package:frisbee_app/data/repositories/personal/personal_repository_api.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../testing/fakes.dart';

void main() {
  late List<Map<String, Object?>> sent;
  late Map<String, http.Response Function()> routes;

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  PersonalDetailsRepositoryApi repo({AccountGate? gate}) =>
      PersonalDetailsRepositoryApi(
        gate: gate,
        api: ApiClient(
          baseUrl: Uri.parse('https://api.test'),
          auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1')),
          client: MockClient((req) async {
            sent.add({
              'method': req.method,
              'path': req.url.path,
              if (req.body.isNotEmpty) 'body': jsonDecode(req.body),
            });
            return (routes['${req.method} ${req.url.path}'] ??
                () => json({}))();
          }),
        ),
        auth: FakeAuthRepository(user: const AppUser(uid: 'u1')),
      );

  setUp(() {
    sent = [];
    routes = {
      'GET /v1/me/personal/status': () =>
          json({'complete': false, 'required': true}),
    };
  });

  group('the sign-up birthday through the API', () {
    test('saves just the date, leaving the details incomplete', () async {
      final r = repo();
      await r.refreshStatus();
      final result = await r.saveSignUpBirthDate(DateTime(1995, 4, 2));
      expect(result, isA<Ok<void>>());
      expect(sent.last, {
        'method': 'PUT',
        'path': '/v1/me/personal/birth-date',
        'body': {'birthDate': '1995-04-02'},
      });
      expect(r.mustComplete, isTrue);
    });

    test('under 13 by the API is a TooYoungException', () async {
      routes['PUT /v1/me/personal/birth-date'] = () => json({
        'error': {
          'code': 'failed_precondition',
          'message': adultOnlyMessage,
          'fields': {'birthDate': adultOnlyMessage},
        },
      }, 412);
      final result = await repo().saveSignUpBirthDate(DateTime(2020, 1, 1));
      expect(result, isA<Error<void>>());
      expect((result as Error<void>).error, isA<TooYoungException>());
    });

    test('load reads it back for About you', () async {
      routes['GET /v1/me/personal'] = () => json({
        'details': null,
        'email': 'pat@x.test',
        'signUpBirthDate': '1995-04-02',
      });
      final result = await repo().load();
      final value = (result as Ok).value;
      expect(value.details, isNull);
      expect(value.signUpBirthDate, DateTime.utc(1995, 4, 2));
    });

    test('without an API it fails softly', () async {
      final r = PersonalDetailsRepositoryApi(
        api: null,
        auth: FakeAuthRepository(user: const AppUser(uid: 'u1')),
      );
      expect(
        await r.saveSignUpBirthDate(DateTime(1995, 4, 2)),
        isA<Error<void>>(),
      );
    });
  });

  group('the account gate', () {
    final details = PersonalDetails(
      legalFirstName: 'Pat',
      legalLastName: 'Lee',
      birthDate: DateTime(1995, 4, 2),
      phone: '555-010-2030',
      gender: Gender.unspecified,
      address: const Address(
        line1: '1 Main St',
        city: 'Boston',
        region: 'MA',
        postalCode: '02110',
      ),
    );

    http.Response refusal(String message) => json({
      'error': {
        'code': 'failed_precondition',
        'message': message,
        'fields': {'birthDate': message},
      },
    }, 412);

    test(
      'under 18 at save: TooYoungException with the server text, dead end',
      () async {
        routes['PUT /v1/me/personal'] = () => refusal(adultOnlyMessage);
        final gate = AccountGate();
        final result = await repo(gate: gate).save(details);
        final error = (result as Error<void>).error;
        expect(error, isA<TooYoungException>());
        expect(error.toString(), adultOnlyMessage);
        expect(gate.underAge, isTrue);
      },
    );

    test(
      'a changed saved birth date: BirthDateLockedException + hint',
      () async {
        routes['PUT /v1/me/personal'] = () => refusal(birthDateLockedMessage);
        final gate = AccountGate();
        final result = await repo(gate: gate).save(details);
        final error = (result as Error<void>).error;
        expect(error, isA<BirthDateLockedException>());
        expect(error.toString(), contains(birthDateLockedMessage));
        expect(error.toString(), contains('support@stall10.app'));
        // Locked is not under-age: no dead end.
        expect(gate.underAge, isFalse);
      },
    );

    test('the sign-up date save is mapped the same way', () async {
      routes['PUT /v1/me/personal/birth-date'] = () =>
          refusal(birthDateLockedMessage);
      final result = await repo().saveSignUpBirthDate(DateTime(1996, 1, 1));
      expect((result as Error<void>).error, isA<BirthDateLockedException>());
    });

    test('a saved birth date or details clear the age step', () async {
      final gate = AccountGate()..report(['age', 'terms']);
      final r = repo(gate: gate);
      await r.saveSignUpBirthDate(DateTime(1995, 4, 2));
      expect(gate.has('age'), isFalse);
      expect(gate.has('terms'), isTrue);

      gate.report(['age']);
      await r.save(details);
      expect(gate.has('age'), isFalse);
    });

    test('the details body has no guardian', () async {
      await repo().save(details);
      final body = sent.last['body']! as Map;
      expect(body.containsKey('guardian'), isFalse);
      expect(body['birthDate'], '1995-04-02');
    });

    test('a status answer with refreshToken is still read', () async {
      routes['GET /v1/me/personal/status'] = () =>
          json({'complete': false, 'required': true, 'refreshToken': true});
      final r = repo();
      await r.refreshStatus();
      expect(r.status?.required, isTrue);
      expect(r.checkFailed, isFalse);
    });

    test('a failed status check stays fail-closed', () async {
      routes['GET /v1/me/personal/status'] = () => json({'error': 'x'}, 500);
      final r = repo();
      await r.refreshStatus();
      expect(r.checkFailed, isTrue);
      expect(r.status, isNull);
    });
  });
}
