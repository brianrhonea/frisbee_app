import 'dart:async';

import 'package:flutter/material.dart';

import 'package:frisbee_app/data/repositories/meeting/meeting_repository.dart';
import 'package:frisbee_app/data/repositories/meeting/meeting_settings_repository.dart';
import 'package:frisbee_app/data/services/meeting_call.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/meeting.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/utils/result.dart';

class FakeMeetingRepository implements MeetingRepository {
  final meetings = <String, TeamMeeting>{};

  /// meetingId → uid → request.
  final requests = <String, Map<String, JoinRequest>>{};

  /// meetingId → messages, oldest first.
  final messages = <String, List<ChatMessage>>{};
  final _changes = StreamController<void>.broadcast();

  /// What [joinToken] returns; an error result keeps people out.
  Result<MeetingAccess> token = const Result.ok(
    MeetingAccess(url: 'wss://test', token: 'jwt'),
  );
  int tokenRequests = 0;
  final ended = <String>[];

  void emit() => _changes.add(null);

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  @override
  Stream<List<TeamMeeting>> watchMeetings(Team team, String uid) => _watch(
    () =>
        meetings.values.where((m) => m.canSee(team, uid)).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
  );

  @override
  Stream<TeamMeeting?> watchMeeting(String teamId, String meetingId) =>
      _watch(() => meetings[meetingId]);

  @override
  Future<Result<String>> saveMeeting(
    String teamId,
    TeamMeeting meeting,
    String uid,
  ) async {
    final id = meeting.isNew ? 'm${meetings.length + 1}' : meeting.id;
    final old = meetings[id];
    meetings[id] = TeamMeeting(
      id: id,
      title: meeting.title,
      startsAt: meeting.startsAt,
      endsAt: meeting.endsAt,
      notes: meeting.notes,
      inviteRoles: meeting.inviteRoles,
      inviteUsers: meeting.inviteUsers,
      requireApproval: meeting.requireApproval,
      status: old?.status ?? MeetingStatus.scheduled,
      rsvps: old?.rsvps ?? const {},
      createdBy: old?.createdBy ?? uid,
    );
    emit();
    return Result.ok(id);
  }

  @override
  Future<Result<void>> deleteMeeting(String teamId, String meetingId) async {
    meetings.remove(meetingId);
    emit();
    return const Result.ok(null);
  }

  TeamMeeting _with(
    TeamMeeting m, {
    MeetingStatus? status,
    Map<String, MeetingRsvp>? rsvps,
  }) => TeamMeeting(
    id: m.id,
    title: m.title,
    startsAt: m.startsAt,
    endsAt: m.endsAt,
    notes: m.notes,
    inviteRoles: m.inviteRoles,
    inviteUsers: m.inviteUsers,
    requireApproval: m.requireApproval,
    status: status ?? m.status,
    rsvps: rsvps ?? m.rsvps,
    createdBy: m.createdBy,
  );

  /// Changes a meeting's status, as an admin elsewhere would.
  void setStatus(String meetingId, MeetingStatus status) {
    meetings[meetingId] = _with(meetings[meetingId]!, status: status);
    emit();
  }

  @override
  Future<Result<void>> setRsvp(
    String teamId,
    String meetingId,
    String uid,
    MeetingRsvp? answer,
  ) async {
    final m = meetings[meetingId]!;
    final rsvps = {...m.rsvps};
    answer == null ? rsvps.remove(uid) : rsvps[uid] = answer;
    meetings[meetingId] = _with(m, rsvps: rsvps);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> startMeeting(
    String teamId,
    String meetingId,
    String uid,
  ) async {
    setStatus(meetingId, MeetingStatus.live);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> endMeeting(String teamId, String meetingId) async {
    ended.add(meetingId);
    setStatus(meetingId, MeetingStatus.ended);
    return const Result.ok(null);
  }

  @override
  Stream<List<JoinRequest>> watchJoinRequests(
    String teamId,
    String meetingId,
  ) => _watch(() => (requests[meetingId] ?? const {}).values.toList());

  @override
  Stream<JoinRequest?> watchMyJoinRequest(
    String teamId,
    String meetingId,
    String uid,
  ) => _watch(() => requests[meetingId]?[uid]);

  @override
  Future<Result<void>> requestToJoin(
    String teamId,
    String meetingId,
    AppUser user,
  ) async {
    (requests[meetingId] ??= {})[user.uid] = JoinRequest(
      uid: user.uid,
      name: user.label,
      requestedAt: DateTime.now(),
    );
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> cancelJoinRequest(
    String teamId,
    String meetingId,
    String uid,
  ) async {
    requests[meetingId]?.remove(uid);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> decideJoinRequest(
    String teamId,
    String meetingId,
    String uid, {
    required bool admit,
    required String adminUid,
  }) async {
    final r = requests[meetingId]![uid]!;
    requests[meetingId]![uid] = JoinRequest(
      uid: uid,
      name: r.name,
      status: admit ? JoinRequestStatus.admitted : JoinRequestStatus.denied,
      requestedAt: r.requestedAt,
    );
    emit();
    return const Result.ok(null);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(
    String teamId,
    String meetingId, {
    required int limit,
  }) => _watch(() => List.of(messages[meetingId] ?? const <ChatMessage>[]));

  @override
  Future<Result<void>> sendMessage(
    String teamId,
    String meetingId, {
    required AppUser author,
    required String text,
  }) async {
    final list = messages[meetingId] ??= [];
    list.add(
      ChatMessage(
        id: 'msg${list.length + 1}',
        authorId: author.uid,
        authorName: author.label,
        text: text,
        createdAt: DateTime.now(),
      ),
    );
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteMessage(
    String teamId,
    String meetingId,
    String messageId,
  ) async {
    messages[meetingId]?.removeWhere((m) => m.id == messageId);
    emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<MeetingAccess>> joinToken(
    String teamId,
    String meetingId,
  ) async {
    tokenRequests++;
    return token;
  }
}

class FakeCallVideo implements CallVideo {
  const FakeCallVideo(this.label);

  final String label;

  @override
  Widget view({bool mirror = false, bool cover = true}) =>
      Text('video:$label${mirror ? ':mirrored' : ''}');
}

class FakeCameraPreview implements CameraPreview {
  FakeCameraPreview(this.deviceId);

  final String? deviceId;
  bool disposed = false;

  @override
  CallVideo get video => FakeCallVideo('preview:${deviceId ?? 'default'}');

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeMeetingCall extends MeetingCall {
  CallSetup? setup;
  MeetingAccess? access;
  bool left = false;
  bool _mic = false;
  bool _camera = false;
  bool _screen = false;
  String? screenSource;
  CallEndReason? _endReason;
  final volumes = <String, double>{};
  final usedDevices = <MediaDeviceInfo>[];

  /// Everyone but the user.
  List<CallParticipant> remotes = const [];

  @override
  Future<void> connect(MeetingAccess access, CallSetup setup) async {
    this.access = access;
    this.setup = setup;
    _mic = setup.micOn;
    _camera = setup.cameraOn;
    notifyListeners();
  }

  @override
  bool get connected => access != null && !left;

  @override
  List<CallParticipant> get participants => [
    CallParticipant(
      uid: 'me',
      name: 'Me',
      isLocal: true,
      micOn: _mic,
      camera: _camera ? const FakeCallVideo('me') : null,
      screen: _screen ? const FakeCallVideo('my-screen') : null,
    ),
    ...remotes,
  ];

  void setRemotes(List<CallParticipant> people) {
    remotes = people;
    notifyListeners();
  }

  void end(CallEndReason reason) {
    _endReason = reason;
    notifyListeners();
  }

  @override
  bool get micOn => _mic;
  @override
  bool get cameraOn => _camera;
  @override
  bool get screenSharing => _screen;
  @override
  CallEndReason? get endReason => _endReason;

  @override
  Future<void> setMicOn(bool on) async {
    _mic = on;
    notifyListeners();
  }

  @override
  Future<void> setCameraOn(bool on) async {
    _camera = on;
    notifyListeners();
  }

  @override
  Future<void> setScreenSharing(bool on, {String? sourceId}) async {
    _screen = on;
    screenSource = sourceId;
    notifyListeners();
  }

  @override
  Future<void> useDevice(MediaDeviceInfo device) async =>
      usedDevices.add(device);

  @override
  void setVolume(String uid, double volume) => volumes[uid] = volume;

  @override
  Future<void> leave() async => left = true;
}

class FakeMeetingMediaService implements MeetingMediaService {
  List<MediaDeviceInfo> deviceList = const [
    MediaDeviceInfo(
      id: 'mic1',
      label: 'Desk mic',
      kind: MediaDeviceKind.audioInput,
    ),
    MediaDeviceInfo(
      id: 'mic2',
      label: 'Headset',
      kind: MediaDeviceKind.audioInput,
    ),
    MediaDeviceInfo(
      id: 'cam1',
      label: 'Webcam',
      kind: MediaDeviceKind.videoInput,
    ),
    MediaDeviceInfo(
      id: 'spk1',
      label: 'Speakers',
      kind: MediaDeviceKind.audioOutput,
    ),
  ];
  bool micAllowed = true;
  bool cameraAllowed = true;
  bool screenShare = true;
  bool picker = false;
  String? pickedSource = 'screen:1';
  final previews = <FakeCameraPreview>[];
  final calls = <FakeMeetingCall>[];
  final _deviceChanges = StreamController<void>.broadcast();

  FakeMeetingCall get lastCall => calls.last;

  @override
  Future<List<MediaDeviceInfo>> devices() async => deviceList;

  @override
  Stream<void> get deviceChanges => _deviceChanges.stream;

  @override
  Future<CameraPreview> previewCamera(String? deviceId) async {
    if (!cameraAllowed) throw Exception('Permission denied');
    final p = FakeCameraPreview(deviceId);
    previews.add(p);
    return p;
  }

  @override
  Future<bool> requestMicrophone() async => micAllowed;

  @override
  bool get canShareScreen => screenShare;

  @override
  bool get picksScreenSource => picker;

  @override
  Future<String?> pickScreenSource(BuildContext context) async => pickedSource;

  @override
  bool get canPickSpeaker => true;

  @override
  MeetingCall createCall() {
    final call = FakeMeetingCall();
    calls.add(call);
    return call;
  }
}

class FakeMeetingSettingsRepository implements MeetingSettingsRepository {
  FakeMeetingSettingsRepository([this.saved = const MeetingSettings()]);

  MeetingSettings saved;

  @override
  Future<MeetingSettings> load() async => saved;

  @override
  Future<void> save(MeetingSettings settings) async => saved = settings;
}
