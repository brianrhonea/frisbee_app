import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/meeting.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';

/// Team meetings: the schedule entry, RSVPs, join requests and the
/// meeting's chat. The call itself goes through `MeetingCall`.
abstract class MeetingRepository {
  /// Meetings [uid] can see on [team], soonest first. Admins see them all.
  Stream<List<TeamMeeting>> watchMeetings(Team team, String uid);

  /// Emits null if the meeting is deleted.
  Stream<TeamMeeting?> watchMeeting(String teamId, String meetingId);

  /// Creates the meeting when [TeamMeeting.isNew], otherwise updates its
  /// details, leaving RSVPs and status intact. Returns the meeting id.
  Future<Result<String>> saveMeeting(
    String teamId,
    TeamMeeting meeting,
    String uid,
  );

  /// Deletes the meeting, its chat and its join requests.
  Future<Result<void>> deleteMeeting(String teamId, String meetingId);

  /// Sets [uid]'s answer, or clears it when [answer] is null.
  Future<Result<void>> setRsvp(
    String teamId,
    String meetingId,
    String uid,
    MeetingRsvp? answer,
  );

  /// Opens the meeting so invitees can join. Admins only.
  Future<Result<void>> startMeeting(
    String teamId,
    String meetingId,
    String uid,
  );

  /// Closes the meeting for everyone. Admins only.
  Future<Result<void>> endMeeting(String teamId, String meetingId);

  /// Join requests, oldest first. Admins only.
  Stream<List<JoinRequest>> watchJoinRequests(String teamId, String meetingId);

  /// [uid]'s own join request; null until they ask.
  Stream<JoinRequest?> watchMyJoinRequest(
    String teamId,
    String meetingId,
    String uid,
  );

  /// Asks an admin to let [user] in, or asks again after being turned away.
  Future<Result<void>> requestToJoin(
    String teamId,
    String meetingId,
    AppUser user,
  );

  Future<Result<void>> cancelJoinRequest(
    String teamId,
    String meetingId,
    String uid,
  );

  /// Lets [uid] in, or turns them away. Admins only.
  Future<Result<void>> decideJoinRequest(
    String teamId,
    String meetingId,
    String uid, {
    required bool admit,
    required String adminUid,
  });

  /// The newest [limit] chat messages, oldest first.
  Stream<List<ChatMessage>> watchMessages(
    String teamId,
    String meetingId, {
    required int limit,
  });

  /// Posts a text message to the meeting chat.
  Future<Result<void>> sendMessage(
    String teamId,
    String meetingId, {
    required AppUser author,
    required String text,
  });

  Future<Result<void>> deleteMessage(
    String teamId,
    String meetingId,
    String messageId,
  );

  /// A token to connect to the meeting's call. Fails unless the meeting is
  /// live and [teamId]'s rules let the signed-in user in.
  Future<Result<MeetingAccess>> joinToken(String teamId, String meetingId);
}
