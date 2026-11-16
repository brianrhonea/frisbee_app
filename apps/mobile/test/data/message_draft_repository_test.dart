import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/draft/message_draft_repository.dart';
import 'package:frisbee_app/data/services/shared_preferences_service.dart';
import 'package:frisbee_app/domain/models/app_user.dart';

import '../testing/fakes.dart';

class _MemoryPrefs implements SharedPreferencesService {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// Prefs whose reads wait for [gate].
class _SlowPrefs extends _MemoryPrefs {
  final gate = Completer<void>();

  @override
  Future<String?> getString(String key) async {
    await gate.future;
    return super.getString(key);
  }
}

const _other = AppUser(uid: 'u2', email: 'b@c.com', displayName: 'Blair');

/// Lets pending writes and loads finish.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late _MemoryPrefs prefs;
  late FakeAuthRepository auth;

  setUp(() {
    prefs = _MemoryPrefs();
    auth = FakeAuthRepository(user: testUser);
  });

  test('keeps drafts under the signed-in user\'s own key', () async {
    final drafts = MessageDraftRepositoryPrefs(
      prefs,
      auth: auth,
      writeDelay: Duration.zero,
    );
    drafts.save('dm_a', 'see you at practice');
    await _settle();
    expect(
      jsonDecode(prefs.values[MessageDraftRepositoryPrefs.keyFor('u1')]!),
      {'dm_a': 'see you at practice'},
    );
    expect(MessageDraftRepositoryPrefs.keyFor('u1'), 'messageDrafts_u1');
    expect(drafts.draft('dm_a'), 'see you at practice');
  });

  test('loads the user\'s drafts and drops the old shared key', () async {
    prefs.values['messageDrafts_u1'] = jsonEncode({'dm_a': 'mine'});
    prefs.values['messageDrafts_u2'] = jsonEncode({'dm_a': 'theirs'});
    prefs.values[MessageDraftRepositoryPrefs.legacyKey] = jsonEncode({
      'dm_a': 'anyone',
    });
    final drafts = MessageDraftRepositoryPrefs(
      prefs,
      auth: auth,
      writeDelay: Duration.zero,
    );
    await _settle();
    expect(drafts.draft('dm_a'), 'mine');
    expect(
      prefs.values.containsKey(MessageDraftRepositoryPrefs.legacyKey),
      isFalse,
    );
  });

  test('signing out forgets the drafts, in memory and on the device', () async {
    final drafts = MessageDraftRepositoryPrefs(
      prefs,
      auth: auth,
      writeDelay: Duration.zero,
    );
    drafts.save('dm_a', 'saved');
    await _settle();
    drafts.save('dm_b', 'still being typed');

    auth.setUser(null);
    await _settle();
    expect(drafts.draft('dm_a'), '');
    expect(drafts.draft('dm_b'), '');
    expect(prefs.values.containsKey('messageDrafts_u1'), isFalse);

    // Nothing is kept while signed out.
    drafts.save('dm_a', 'nobody');
    await _settle();
    expect(prefs.values, isEmpty);
  });

  test(
    'the next user on the device never sees the last one\'s drafts',
    () async {
      final drafts = MessageDraftRepositoryPrefs(
        prefs,
        auth: auth,
        writeDelay: Duration.zero,
      );
      drafts.save('dm_a', 'from u1');
      auth.setUser(_other);
      await _settle();
      expect(drafts.draft('dm_a'), '');
      expect(prefs.values.containsKey('messageDrafts_u1'), isFalse);
      expect(prefs.values.containsKey('messageDrafts_u2'), isFalse);
    },
  );

  test('a load that finishes after signing out is ignored', () async {
    prefs.values['messageDrafts_u1'] = jsonEncode({'dm_a': 'mine'});
    final drafts = MessageDraftRepositoryPrefs(
      prefs,
      auth: auth,
      writeDelay: Duration.zero,
    );
    auth.setUser(null);
    await _settle();
    expect(drafts.draft('dm_a'), '');
    auth.setUser(_other);
    await _settle();
    expect(drafts.draft('dm_a'), '');
  });

  test('a save before the stored drafts load keeps them', () async {
    final slow = _SlowPrefs()
      ..values['messageDrafts_u1'] = jsonEncode({
        'dm_a': 'stored',
        'dm_b': 'cleared later',
      });
    final drafts = MessageDraftRepositoryPrefs(
      slow,
      auth: auth,
      writeDelay: Duration.zero,
    );
    drafts.save('dm_c', 'typed first');
    drafts.save('dm_b', '');
    await _settle();
    // Not written over while the load is still going.
    expect(jsonDecode(slow.values['messageDrafts_u1']!), {
      'dm_a': 'stored',
      'dm_b': 'cleared later',
    });

    slow.gate.complete();
    await _settle();
    expect(drafts.draft('dm_a'), 'stored');
    expect(drafts.draft('dm_b'), '');
    expect(drafts.draft('dm_c'), 'typed first');
    expect(jsonDecode(slow.values['messageDrafts_u1']!), {
      'dm_a': 'stored',
      'dm_c': 'typed first',
    });
  });
}
