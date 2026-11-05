import 'package:flutter/foundation.dart';

import '../../../utils/result.dart';
import '../../services/meeting_call.dart';

/// The voice channel the user is in.
class VoiceChannel {
  const VoiceChannel({
    required this.teamId,
    required this.roomId,
    required this.name,
    this.teamName = '',
  });

  final String teamId;
  final String roomId;
  final String name;
  final String teamName;

  bool isRoom(String teamId, String roomId) =>
      this.teamId == teamId && this.roomId == roomId;
}

/// The user's voice connection, like Discord's: one channel at a time,
/// kept up while they move around the app until they disconnect. Notifies
/// on any change to the channel, the call or who's in it.
abstract class VoiceRepository extends ChangeNotifier {
  /// The channel joined or being joined; null when disconnected.
  VoiceChannel? get channel;

  bool get connecting;
  bool get connected;

  /// False when the user can only listen in [channel].
  bool get canSpeak;
  bool get micOn;

  /// Everyone in the call, the user first.
  List<CallParticipant> get participants;

  /// Why the call dropped on its own, until the next join.
  String? get notice;

  bool isIn(String teamId, String roomId) =>
      channel?.isRoom(teamId, roomId) ?? false;

  /// Joins [channel], leaving any other first.
  Future<Result<void>> join(VoiceChannel channel);

  Future<Result<void>> leave();

  Future<Result<void>> setMicOn(bool on);
}
