// Things the user sent while offline (or while the server couldn't be
// reached), kept on the device until they go out: messages, team chat,
// posts, team posts and comments. The same rules as the website's queue
// (packages/shared/src/outbox.ts); test/data/outbox_policy_test.dart
// writes the shared fixtures both are checked against.

/// What a queued item creates.
enum OutboxKind { directMessage, teamChat, userPost, teamPost, comment }

/// Where a queued item stands.
enum OutboxState {
  /// Waiting for a connection (or its next try).
  waiting,

  /// Going out now.
  sending,

  /// Turned down by the server (e.g. removed from the team); the user
  /// retries or discards it.
  failed,
}

/// How a failed attempt is treated.
enum OutboxFailure {
  /// No connection: wait for one, then try again.
  network,

  /// The server had a problem or asked to slow down: try again later.
  retry,

  /// The server said no: keep it for the user to retry or discard.
  permanent,

  /// It's already there (an earlier try went through but its answer was
  /// lost): done.
  sent,
}

abstract final class OutboxLimits {
  /// Items kept per device.
  static const maxItems = 50;

  /// Attachment bytes kept per device.
  static const maxBytes = 200 * 1024 * 1024;

  /// Waits between tries after a server error, then the last one repeats.
  static const backoffSeconds = [5, 15, 30, 60, 120, 300];

  /// How long a send may hang (a Firestore write offline waits instead of
  /// failing) before it's queued instead.
  static const sendTimeout = Duration(seconds: 15);
}

/// The wait before try number [attempts] + 1 after a server error.
Duration outboxBackoff(int attempts) {
  const s = OutboxLimits.backoffSeconds;
  return Duration(seconds: s[attempts.clamp(0, s.length - 1)]);
}

/// How an error [code] is treated: an API error code
/// (packages/shared/src/api.ts) or a Firebase one.
OutboxFailure outboxFailureOf(String code) => switch (code) {
  // Can't reach the server. (A sign-in token that can't refresh offline
  // comes as 'unavailable'; a real 'unauthenticated' is the user's to sort
  // out, so it's permanent.)
  'unavailable' ||
  'network' ||
  'network-request-failed' ||
  'deadline-exceeded' ||
  'retry-limit-exceeded' => OutboxFailure.network,
  'internal' ||
  'unknown' ||
  'aborted' ||
  'resource-exhausted' ||
  'resource_exhausted' => OutboxFailure.retry,
  'already_exists' || 'already-exists' => OutboxFailure.sent,
  _ => OutboxFailure.permanent,
};

/// An attachment kept on the device until its item goes out.
class OutboxFile {
  const OutboxFile({
    required this.name,
    required this.path,
    required this.size,
  });

  final String name;

  /// Where it's kept, relative to the outbox's folder.
  final String path;
  final int size;

  Map<String, Object?> toJson() => {'name': name, 'path': path, 'size': size};

  factory OutboxFile.fromJson(Map<String, Object?> j) => OutboxFile(
    name: j['name'] as String? ?? 'file',
    path: j['path'] as String? ?? '',
    size: (j['size'] as num?)?.toInt() ?? 0,
  );
}

/// A file of a queued item that's uploaded and ready (`/v1/uploads`), kept
/// with the job so sending it again doesn't upload it again.
class ReadyUpload {
  const ReadyUpload({
    required this.id,
    required this.name,
    required this.contentType,
    required this.size,
  });

  final String id;
  final String name;
  final String contentType;
  final int size;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'contentType': contentType,
    'size': size,
  };

  static ReadyUpload? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return ReadyUpload(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'file',
      contentType: j['contentType'] as String? ?? 'application/octet-stream',
      size: (j['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One queued item. [id] is the id the message, post or comment gets, the
/// same on every try, so a send that went through but whose answer was
/// lost can't make a second copy.
class OutboxJob {
  const OutboxJob({
    required this.id,
    required this.uid,
    required this.kind,
    required this.createdAt,
    required this.target,
    required this.label,
    required this.payload,
    this.files = const [],
    this.uploads = const {},
    this.version = currentVersion,
    this.state = OutboxState.waiting,
    this.attempts = 0,
    this.nextTryAt,
    this.error,
  });

  /// The payload layout new jobs are written in. Version 1 (no `version`
  /// saved) is what builds before the API switch queued: a comment's
  /// `parentId`, chat `replyTo` objects, a post's editable map.
  /// [OutboxPayloads] maps those to today's request bodies.
  static const currentVersion = 2;

  final String id;

  /// Who queued it: it only goes out signed in as them.
  final String uid;
  final OutboxKind kind;
  final DateTime createdAt;

  /// Where it goes: the conversation, `team/room`, team or post. Items for
  /// the same place go out in order.
  final String target;

  /// What the user sees, e.g. "Message to Sam".
  final String label;

  /// What's needed to send it again (the repository's own fields).
  final Map<String, Object?> payload;
  final List<OutboxFile> files;

  /// Files already uploaded and ready, by index into [files].
  final Map<int, ReadyUpload> uploads;

  /// The payload layout ([currentVersion] for new jobs).
  final int version;
  final OutboxState state;
  final int attempts;
  final DateTime? nextTryAt;

  /// Why the server turned it down, when [state] is failed.
  final String? error;

  /// The text it starts with, for lists and pending bubbles.
  String get preview {
    final t = (payload['text'] ?? payload['body'] ?? '') as String;
    return t.trim();
  }

  int get bytes => files.fold(0, (n, f) => n + f.size);

  OutboxJob copyWith({
    Map<int, ReadyUpload>? uploads,
    OutboxState? state,
    int? attempts,
    DateTime? Function()? nextTryAt,
    String? Function()? error,
  }) => OutboxJob(
    id: id,
    uid: uid,
    kind: kind,
    createdAt: createdAt,
    target: target,
    label: label,
    payload: payload,
    files: files,
    uploads: uploads ?? this.uploads,
    version: version,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    nextTryAt: nextTryAt != null ? nextTryAt() : this.nextTryAt,
    error: error != null ? error() : this.error,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'uid': uid,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'target': target,
    'label': label,
    'payload': payload,
    'files': [for (final f in files) f.toJson()],
    'uploads': {for (final e in uploads.entries) '${e.key}': e.value.toJson()},
    'version': version,
    'state': state.name,
    'attempts': attempts,
    'nextTryAt': nextTryAt?.toIso8601String(),
    'error': error,
  };

  static OutboxJob? fromJson(Map<String, Object?> j) {
    final kind = OutboxKind.values
        .where((k) => k.name == j['kind'])
        .firstOrNull;
    final id = j['id'];
    final uid = j['uid'];
    if (kind == null || id is! String || uid is! String) return null;
    // An item that was going out when the app closed goes out again.
    final state = OutboxState.values
        .where((s) => s.name == j['state'] && s != OutboxState.sending)
        .firstOrNull;
    return OutboxJob(
      id: id,
      uid: uid,
      kind: kind,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      target: j['target'] as String? ?? '',
      label: j['label'] as String? ?? '',
      payload: Map<String, Object?>.from(j['payload'] as Map? ?? const {}),
      files: [
        for (final f in (j['files'] as List?) ?? const [])
          if (f is Map) OutboxFile.fromJson(Map<String, Object?>.from(f)),
      ],
      uploads: {
        for (final e in ((j['uploads'] as Map?) ?? const {}).entries)
          if (int.tryParse('${e.key}') case final i?)
            if (ReadyUpload.fromJson(e.value) case final u?) i: u,
      },
      // A job saved before versions existed is version 1.
      version: (j['version'] as num?)?.toInt() ?? 1,
      state: state ?? OutboxState.waiting,
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      nextTryAt: DateTime.tryParse(j['nextTryAt'] as String? ?? ''),
      error: j['error'] as String?,
    );
  }
}

/// Values made JSON-safe for a queued payload: dates as ISO strings, which
/// the models' fromMap read back (parseDate).
Object? jsonSafe(Object? v) => switch (v) {
  DateTime d => d.toIso8601String(),
  Map m => {for (final e in m.entries) '${e.key}': jsonSafe(e.value)},
  Iterable l => [for (final x in l) jsonSafe(x)],
  _ => v,
};

/// [job] after a try that ended in [failure] (null: it went through), or
/// null once it's done.
OutboxJob? afterTry(
  OutboxJob job,
  OutboxFailure? failure,
  DateTime now, {
  String? message,
}) => switch (failure) {
  null || OutboxFailure.sent => null,
  // Waits for the connection; the try doesn't count.
  OutboxFailure.network => job.copyWith(
    state: OutboxState.waiting,
    nextTryAt: () => null,
  ),
  OutboxFailure.retry => job.copyWith(
    state: OutboxState.waiting,
    attempts: job.attempts + 1,
    nextTryAt: () => now.add(outboxBackoff(job.attempts)),
  ),
  OutboxFailure.permanent => job.copyWith(
    state: OutboxState.failed,
    attempts: job.attempts + 1,
    nextTryAt: () => null,
    error: () => message ?? "Couldn't be sent.",
  ),
};

/// The items to send now for [uid], oldest first. Within a place they go
/// in order: one waiting for its next try holds back the ones after it
/// (a failed one doesn't, it waits for the user).
List<OutboxJob> dueJobs(List<OutboxJob> jobs, String uid, DateTime now) {
  final held = <String>{};
  final due = <OutboxJob>[];
  final mine = [
    for (final j in jobs)
      if (j.uid == uid) j,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  for (final j in mine) {
    if (j.state != OutboxState.waiting) continue;
    if (held.contains(j.target)) continue;
    if (j.nextTryAt != null && j.nextTryAt!.isAfter(now)) {
      held.add(j.target);
      continue;
    }
    due.add(j);
  }
  return due;
}

/// The queue's place for a team chat room's messages.
String teamChatTarget(String teamId, String roomId) => '$teamId/$roomId';
