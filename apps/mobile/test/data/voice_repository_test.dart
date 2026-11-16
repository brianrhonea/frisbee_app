import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/voice/voice_repository.dart';
import 'package:frisbee_app/data/repositories/voice/voice_repository_livekit.dart';
import 'package:frisbee_app/data/services/callable_client.dart';
import 'package:frisbee_app/data/services/meeting_call.dart';
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

/// A call whose hang-up waits for [gate].
class _SlowLeaveCall extends FakeMeetingCall {
  _SlowLeaveCall(this.gate);
  final Completer<void> gate;

  @override
  Future<void> leave() async {
    await gate.future;
    left = true;
  }
}

/// Media whose calls hang up only once [gate] completes.
class _SlowLeaveMedia extends FakeMeetingMediaService {
  final gate = Completer<void>();

  @override
  MeetingCall createCall() {
    final call = _SlowLeaveCall(gate);
    calls.add(call);
    return call;
  }
}

/// Counts open team subscriptions.
class _CountingTeams extends FakeTeamRepository {
  var open = 0;

  @override
  Stream<Team?> watchTeam(String teamId) {
    final inner = super.watchTeam(teamId);
    late StreamController<Team?> controller;
    StreamSubscription<Team?>? sub;
    controller = StreamController<Team?>(
      onListen: () {
        open++;
        sub = inner.listen(controller.add, onError: controller.addError);
      },
      onCancel: () {
        open--;
        return sub?.cancel();
      },
    );
    return controller.stream;
  }
}

/// A room stream that sends one value and ends the first time.
class _EndingChats extends FakeChatRepository {
  var opened = 0;

  @override
  Stream<ChatRoom?> watchRoom(String teamId, String roomId) {
    opened++;
    if (opened == 1) return Stream.value(rooms[roomId]);
    return super.watchRoom(teamId, roomId);
  }
}

ChatRoom _room(String id) => ChatRoom(
  id: id,
  name: id,
  kind: ChatRoomKind.voice,
  readRoles: const {ChatAudience.everyone},
  writeRoles: const {ChatAudience.everyone},
);

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
  test(
    'switching channels quickly ends in the last one, watched once',
    () async {
      final slow = _SlowLeaveMedia();
      final counting = _CountingTeams()..teams.addAll(teams.teams);
      media = slow;
      teams = counting;
      chats.rooms['court'] = _room('court');
      chats.rooms['pit'] = _room('pit');
      voice.dispose();
      voice = make();
      await joined();

      const court = VoiceChannel(teamId: 't1', roomId: 'court', name: 'Court');
      const pit = VoiceChannel(teamId: 't1', roomId: 'pit', name: 'Pit');
      final first = voice.join(court); // Waits for the lounge hang-up.
      final second = voice.join(pit);
      slow.gate.complete();
      await Future.wait([first, second]);
      await pumpEventQueue();

      expect(voice.channel?.roomId, 'pit');
      expect(voice.connected, isTrue);
      expect(counting.open, 1, reason: 'no leaked watchers');
      expect(slow.calls.where((c) => !c.left), hasLength(1));
    },
  );

  test("a team that hasn't loaded yet doesn't drop the call", () async {
    final team = teams.teams.remove('t1')!;
    await voice.join(channel);
    await pumpEventQueue();
    expect(voice.channel, isNotNull);

    teams.teams['t1'] = team;
    teams.changed();
    await pumpEventQueue();
    expect(voice.channel, isNotNull);

    // Once seen, the team going away drops it.
    teams.teams.remove('t1');
    teams.changed();
    await pumpEventQueue();
    expect(voice.channel, isNull);
    expect(voice.notice, voiceLostAccessNotice);
  });

  test('a room stream that ends is watched again', () async {
    final ending = _EndingChats()..rooms['lounge'] = _lounge;
    chats = ending;
    voice.dispose();
    voice = make();
    await joined();
    expect(ending.opened, 1);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(ending.opened, 2);
    ending.rooms.remove('lounge');
    ending.emit();
    await pumpEventQueue();
    expect(voice.channel, isNull);
  });
}
