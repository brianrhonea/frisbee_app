import '../../../domain/models/team_event.dart';
import '../../../utils/result.dart';

abstract class EventRepository {
  /// Events for a team, sorted by start time; with [since], only those
  /// starting on or after that day (reads far fewer documents than the
  /// team's whole history).
  ///
  /// In a school or club community, a member who doesn't manage events
  /// passes [audience] (Team.eventAudienceOf): the ids they hold, so they
  /// get only events shown to them, as firestore.rules requires.
  Stream<List<TeamEvent>> watchEvents(
    String teamId, {
    DateTime? since,
    Set<String>? audience,
  });

  /// Emits null if the event is deleted.
  Stream<TeamEvent?> watchEvent(String teamId, String eventId);

  /// The team's public events, sorted by start time: details only, no
  /// responses. Anyone signed in may read them. [since] as for
  /// [watchEvents].
  Stream<List<TeamEvent>> watchPublicEvents(String teamId, {DateTime? since});

  /// Creates the event when [TeamEvent.isNew], otherwise updates its
  /// editable fields, leaving responses intact. Keeps the public copy in
  /// step with [TeamEvent.isPublic]. [clearVotes] wipes poll
  /// votes, e.g. when the poll is removed. Returns the saved event id.
  ///
  /// A new event with [repeat] is written as a series, one event per
  /// occurrence (returns the first one's id). Editing with
  /// [SeriesScope.following] also changes every later event in its
  /// series: the same details, moved by the same change of date and time.
  Future<Result<String>> saveEvent(
    String teamId,
    TeamEvent event,
    String uid, {
    bool clearVotes = false,
    Repeat? repeat,
    SeriesScope scope = SeriesScope.one,
  });

  /// Deletes the event; [SeriesScope.following] also its series' later ones.
  Future<Result<void>> deleteEvent(
    String teamId,
    String eventId, {
    SeriesScope scope = SeriesScope.one,
  });

  /// Sets [uid]'s RSVP, or clears it (and its note) when [status] is null.
  /// Anything but [RsvpStatus.going] also removes [uid]'s reactions and
  /// votes, since only attendees may react or vote. The note stays.
  Future<Result<void>> setRsvp(
    String teamId,
    String eventId,
    String uid,
    RsvpStatus? status,
  );

  /// Sets [uid]'s note on their answer, or removes it when [note] is
  /// empty. [note] is already cleaned ([cleanRsvpNote]); [uid] must have
  /// answered.
  Future<Result<void>> setRsvpNote(
    String teamId,
    String eventId,
    String uid,
    String note,
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

  // Personal schedule: events only [uid] sees, without responses or polls.

  /// [uid]'s personal events, sorted by start time. [since] as for
  /// [watchEvents].
  Stream<List<TeamEvent>> watchMyEvents(String uid, {DateTime? since});

  /// Emits null if the event is deleted.
  Stream<TeamEvent?> watchMyEvent(String uid, String eventId);

  /// Creates the event when [TeamEvent.isNew], otherwise updates it.
  /// Returns the saved event id. [repeat] and [scope] as in [saveEvent].
  Future<Result<String>> saveMyEvent(
    String uid,
    TeamEvent event, {
    Repeat? repeat,
    SeriesScope scope = SeriesScope.one,
  });

  Future<Result<void>> deleteMyEvent(
    String uid,
    String eventId, {
    SeriesScope scope = SeriesScope.one,
  });
}
