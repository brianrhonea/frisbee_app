import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/voice/voice_repository.dart';
import 'package:frisbee_app/data/repositories/voice/voice_repository_livekit.dart';
import 'package:frisbee_app/data/services/callable_client.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/team.dart';

import '../testing/fakes.dart';
import '../testing/meeting_fakes.dart';

/// Hands out a voice token; [canSpeak] is what it allows.
class _FakeFunctions implements CallableClient {
  bool canSpeak = true;

  @override
  Future<Object?> call(
    String name,
    Map<String, Object?> data, {
    bool signedOut = false,
  }) async => {'url': 'wss://lk', 'token': 'tok', 'canSpeak': canSpeak};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A room stream that fails once with [error], then works.
class _FlakyChats extends FakeChatRepository {
  _FlakyChats(this.error);
  Object? error;
  var opened = 0;

  @override
  Stream<ChatRoom?> watchRoom(String teamId, String roomId) {
    opened++;
    final e = error;
    if (e != null) {
      error = null;
      return Stream.error(e);
    }
    return super.watchRoom(teamId, roomId);
  }
}

const _lounge = ChatRoom(
  id: 'lounge',
  name: 'Lounge',
  kind: ChatRoomKind.voice,
  readRoles: {ChatAudience.everyone},
  writeRoles: {ChatAudience.everyone},
);

void main() {
  late FakeTeamRepository teams;
  late FakeChatRepository chats;
  late FakeAuthRepository auth;
  late FakeMeetingMediaService media;
  late _FakeFunctions functions;
  late VoiceRepositoryLiveKit voice;

  const channel = VoiceChannel(teamId: 't1', roomId: 'lounge', name: 'Lounge');

  VoiceRepositoryLiveKit make() => VoiceRepositoryLiveKit(
    functions: functions,
    media: media,
    settings: FakeMeetingSettingsRepository(),
    teams: teams,
    chats: chats,
    auth: auth,
  );

  setUp(() {
    teams = FakeTeamRepository()
      ..teams['t1'] = teamWith({'o': TeamRole.owner, 'u1': TeamRole.player});
    chats = FakeChatRepository()..rooms['lounge'] = _lounge;
    auth = FakeAuthRepository(user: testUser);
    media = FakeMeetingMediaService();
    functions = _FakeFunctions();
    voice = make();
  });

  tearDown(() => voice.dispose());

  Future<void> joined() async {
    await voice.join(channel);
    await pumpEventQueue();
    expect(voice.connected, isTrue);
  }

  test('losing write access turns the mic off and keeps listening', () async {
    await joined();
    expect(voice.canSpeak, isTrue);
    expect(voice.micOn, isTrue);

    chats.rooms['lounge'] = const ChatRoom(
      id: 'lounge',
      name: 'Lounge',
      kind: ChatRoomKind.voice,
      readRoles: {ChatAudience.everyone},
    );
    chats.emit();
    await pumpEventQueue();

    expect(voice.connected, isTrue);
    expect(voice.canSpeak, isFalse);
    expect(voice.micOn, isFalse);
    await voice.setMicOn(true);
    expect(voice.micOn, isFalse, reason: "can't turn it back on");

    // Given back: talking is allowed again.
    chats.rooms['lounge'] = _lounge;
    chats.emit();
    await pumpEventQueue();
    expect(voice.canSpeak, isTrue);
  });

  test('a listener token stays listen-only even with write access', () async {
    functions.canSpeak = false;
    await joined();
    expect(voice.canSpeak, isFalse);
    expect(voice.micOn, isFalse);
  });

  test('leaving the team drops the call', () async {
    await joined();
    teams.teams['t1'] = teamWith({'o': TeamRole.owner});
    teams.changed();
    await pumpEventQueue();
    expect(voice.channel, isNull);
    expect(media.lastCall.left, isTrue);
    expect(voice.notice, voiceLostAccessNotice);
  });

  test('losing read access drops the call', () async {
    await joined();
    chats.rooms['lounge'] = const ChatRoom(
      id: 'lounge',
      name: 'Lounge',
      kind: ChatRoomKind.voice,
      readRoles: {'captain'},
      writeRoles: {'captain'},
    );
    chats.emit();
    await pumpEventQueue();
    expect(voice.channel, isNull);
    expect(media.lastCall.left, isTrue);
    expect(voice.notice, voiceLostAccessNotice);
  });

  test('the room being deleted closes the channel', () async {
    await joined();
    chats.rooms.remove('lounge');
    chats.emit();
    await pumpEventQueue();
    expect(voice.channel, isNull);
    expect(voice.notice, 'The voice channel closed.');
  });

  test('a permission error on the room drops the call', () async {
    chats = _FlakyChats(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    )..rooms['lounge'] = _lounge;
    voice.dispose();
    voice = make();
    await voice.join(channel);
    await pumpEventQueue();
    expect(voice.channel, isNull);
    expect(voice.notice, voiceLostAccessNotice);
  });

  test('another error on the room resubscribes instead of dropping', () async {
    final flaky = _FlakyChats(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    )..rooms['lounge'] = _lounge;
    chats = flaky;
    voice.dispose();
    voice = make();
    await voice.join(channel);
    await pumpEventQueue();
    expect(voice.channel, isNotNull);
    expect(flaky.opened, 1);
    // Retried after the first backoff (1 s).
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(flaky.opened, 2);
    // Watching again: a later deletion still closes it.
    flaky.rooms.remove('lounge');
    flaky.emit();
    await pumpEventQueue();
    expect(voice.channel, isNull);
  });

  test('signing out disconnects', () async {
    await joined();
    auth.setUser(null);
    await pumpEventQueue();
    expect(voice.channel, isNull);
    expect(media.lastCall.left, isTrue);
  });
}
