import '../../../domain/models/team_event.dart';
import '../../../utils/result.dart';

abstract class EventRepository {
  /// Events for a team, sorted by start time.
  Stream<List<TeamEvent>> watchEvents(String teamId);

  /// Emits null if the event is deleted.
  Stream<TeamEvent?> watchEvent(String teamId, String eventId);

  /// Creates the event when [TeamEvent.isNew], otherwise updates its
  /// editable fields, leaving responses intact. [clearVotes] wipes poll
  /// votes, e.g. when the poll is removed. Returns the saved event id.
  Future<Result<String>> saveEvent(
    String teamId,
    TeamEvent event,
    String uid, {
    bool clearVotes = false,
  });

  Future<Result<void>> deleteEvent(String teamId, String eventId);

  /// Sets [uid]'s RSVP, or clears it when [status] is null. Anything but
  /// [RsvpStatus.going] also removes [uid]'s reactions and votes, since only
  /// attendees may react or vote.
  Future<Result<void>> setRsvp(
    String teamId,
    String eventId,
    String uid,
    RsvpStatus? status,
  );

  Future<Result<void>> setReaction(
    String teamId,
    String eventId,
    String uid,
    Reaction reaction, {
    required bool on,
  });

  /// Replaces [uid]'s poll votes.
  Future<Result<void>> setVotes(
    String teamId,
    String eventId,
    String uid,
    List<String> optionIds,
  );
}
