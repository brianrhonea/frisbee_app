import '../../../domain/models/outbox.dart';
import '../../../domain/models/workout_route.dart';

/// What a queued job sends, as the API's request body, worked out from the
/// job's saved payload. The one place that knows both payload layouts
/// ([OutboxJob.version]): jobs queued by builds before the API switch
/// (version 1) must still go out, so their payloads are mapped to today's
/// bodies. A job that can't be mapped returns null; the queue then marks it
/// failed ("Couldn't be sent") and keeps it for the user, never drops it.
///
/// The bodies leave out `id` (the job's id) and `uploadIds` (made when the
/// files are uploaded); the repositories add them.
abstract final class OutboxPayloads {
  /// The message the user sees on a job that can't be mapped.
  static const unmappable = "Couldn't be sent.";

  static Map<String, Object?>? _map(Object? v) =>
      v is Map ? Map<String, Object?>.from(v) : null;

  static String _string(Object? v) => v is String ? v : '';

  static String? _id(Object? v) => v is String && v.isNotEmpty ? v : null;

  // Comments --------------------------------------------------------------

  /// `POST /v1/posts/:id/comments`: `{body, replyTo?}`.
  ///
  /// Version 1 saved `parentId` (the top-level comment replied to) and
  /// `replyToName`; `parentId` becomes `replyTo`, and the server works out
  /// whose reply it was. A later build saves `replyTo` itself (the comment
  /// replied to, a reply too).
  static Map<String, Object?>? comment(OutboxJob job) {
    final p = job.payload;
    final body = _string(p['body']).trim();
    if (body.isEmpty) return null;
    final replyTo = job.version >= 2
        ? _id(p['replyTo'])
        : _id(p['parentId']) ?? _id(p['replyTo']);
    return {'body': body, 'replyTo': ?replyTo};
  }

  // Chat and direct messages ---------------------------------------------

  /// `{text, replyTo?}` for a team chat or direct message: the saved reply
  /// quote (an object, which the pending bubble shows) becomes its `id`.
  /// An empty text is fine when files go with it.
  static Map<String, Object?> message(OutboxJob job) {
    final p = job.payload;
    final reply = p['replyTo'];
    final replyTo = reply is Map ? _id(reply['id']) : _id(reply);
    return {'text': _string(p['text']).trim(), 'replyTo': ?replyTo};
  }

  // Team posts -----------------------------------------------------------

  /// A team post's request body (`POST /v1/teams/:teamId/posts` without
  /// `id` and `uploadIds`): the saved editable map (`post`) becomes
  /// `{title, body, location, links, public, tournamentKey?}`. Null when
  /// there's nothing to post.
  static Map<String, Object?>? teamPost(OutboxJob job) {
    final post = _map(job.payload['post']);
    if (post == null) return null;
    final body = _string(post['body']);
    if (body.trim().isEmpty && job.files.isEmpty) return null;
    final key = _id(post['tournamentKey']);
    return {
      'title': _string(post['title']).trim(),
      'body': body,
      'location': _string(post['location']).trim(),
      'links': [for (final l in (post['links'] as List?) ?? const []) '$l'],
      'public': post['public'] == true,
      'tournamentKey': ?key,
    };
  }

  // User posts -----------------------------------------------------------

  /// A user post's request body (`POST /v1/posts` without `id` and
  /// `uploadIds`): the saved editable map (`post`) becomes
  /// `{body, links, workout?, shareEvent?, tournament?}`. Null for what
  /// can't be a new post (a repost, or no content).
  static Map<String, Object?>? userPost(OutboxJob job) {
    final post = _map(job.payload['post']);
    if (post == null) return null;
    final kind = post['kind'];
    if (kind == 'repost' || post['repostOf'] != null) return null;
    final workout = _map(post['workout']);
    final event = _map(post['event']);
    final key = _id(post['tournamentKey']);
    final body = _string(post['body']).trim();
    final links = [for (final l in (post['links'] as List?) ?? const []) '$l'];
    final hasPhotos = job.files.isNotEmpty;
    if (body.isEmpty &&
        workout == null &&
        event == null &&
        !hasPhotos &&
        links.isEmpty) {
      return null;
    }
    final Map<String, Object?>? sharedEvent;
    if (event != null) {
      final eventId = _id(event['eventId']);
      if (eventId == null) return null;
      sharedEvent = {'eventId': eventId, 'teamId': _id(event['teamId'])};
    } else {
      sharedEvent = null;
    }
    return {
      'body': body,
      'links': links,
      if (workout != null) 'workout': _workout(workout),
      'shareEvent': ?sharedEvent,
      if (key != null)
        'tournament': {'key': key, 'name': _string(post['tournamentName'])},
    };
  }

  /// A workout in the API's shape (`workoutSchema`): a recorded run keeps
  /// its exact seconds and GPS route (thinned to the API's 4000 points).
  static Map<String, Object?> _workout(Map<String, Object?> w) => {
    'activity': w['activity'],
    'durationMinutes': w['durationMinutes'],
    'durationSeconds': ?w['durationSeconds'],
    'distanceKm': ?w['distanceKm'],
    'effort': ?w['effort'],
    'route': ?_route(w['route']),
    'exercises': [
      for (final e in (w['exercises'] as List?) ?? const [])
        if (e is Map)
          {
            'name': e['name'],
            if (e['sets'] != null) 'sets': e['sets'],
            if (e['reps'] != null) 'reps': e['reps'],
            if (e['weight'] != null) 'weight': e['weight'],
          },
    ],
  };

  /// A route in the API's shape: [WorkoutRoute.toMap] with the path thinned
  /// to at most [WorkoutRoute.maxPoints] points first. Null for none.
  static Map<String, Object?>? _route(Object? raw) {
    if (raw is! Map) return null;
    final route = WorkoutRoute.fromMap(Map<String, dynamic>.from(raw));
    if (route.path.length <= WorkoutRoute.maxPoints) {
      return Map<String, Object?>.from(route.toMap());
    }
    return Map<String, Object?>.from(
      WorkoutRoute(
        path: simplifyPath(route.path, maxPoints: WorkoutRoute.maxPoints),
        splitsMi: route.splitsMi,
        splitsKm: route.splitsKm,
        elevationGainMeters: route.elevationGainMeters,
      ).toMap(),
    );
  }

  /// Why a post's workout can't be sent as it stands, or null: a route
  /// with under 2 points, or more splits than the API takes. Checked before
  /// the request so the person sees it at once.
  static String? workoutProblem(Map<String, Object?>? workout) {
    final raw = workout?['route'];
    if (raw is! Map) return null;
    final r = _route(raw);
    final route = WorkoutRoute.fromMap(Map<String, dynamic>.from(r!));
    if (route.path.length < 2) return 'The route is too short to share.';
    if (route.splitsMi.length > WorkoutRoute.maxSplits ||
        route.splitsKm.length > WorkoutRoute.maxSplits) {
      return 'That route is too long to share.';
    }
    return null;
  }
}
