import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/outbox.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../../services/connectivity_service.dart';
import '../../services/outbox_store.dart';
import '../../services/upload_client.dart';
import '../auth/auth_repository.dart';

/// How one kind of queued item goes out, registered by the repository that
/// makes it (so the item is written exactly as a direct send writes it).
class OutboxHandler {
  const OutboxHandler({required this.send, required this.sent});

  /// Sends [job] as [author], with its attachments, under the job's id.
  final Future<Result<void>> Function(
    OutboxJob job,
    List<NewAttachment> files,
    AppUser author,
  )
  send;

  /// Whether it's already on the server (an earlier try went through).
  final Future<bool> Function(OutboxJob job) sent;
}

/// How [error] is treated by the queue.
OutboxFailure outboxFailureFor(Object error) => switch (error) {
  ApiException(:final code) => outboxFailureOf(code),
  FirebaseException(:final code) => outboxFailureOf(code),
  TimeoutException() ||
  SocketException() ||
  http.ClientException() => OutboxFailure.network,
  _ => OutboxFailure.permanent,
};

String _messageOf(Object e) => switch (e) {
  ApiException(:final message) => message,
  FirebaseException(:final message) => message ?? "Couldn't be sent.",
  _ => "Couldn't be sent.",
};

/// The offline queue: messages, team chat, posts, team posts and comments
/// sent without a connection wait here (on the device, [OutboxStore]) and
/// go out by themselves, in order, once Stall 10 can be reached again.
/// Each keeps the id it was given when the user sent it, so nothing is
/// posted twice. Only items queued by the signed-in user are shown or
/// sent.
class OutboxRepository extends ChangeNotifier implements UploadLedger {
  OutboxRepository({
    required OutboxStore store,
    required ConnectivityService connectivity,
    required AuthRepository auth,
    DateTime Function()? now,
  }) : _store = store,
       _connectivity = connectivity,
       _auth = auth,
       _now = now ?? DateTime.now {
    _connectivity.addListener(_onConnectivity);
    _auth.addListener(_onAuth);
    _loaded = _load();
  }

  final OutboxStore _store;
  final ConnectivityService _connectivity;
  final AuthRepository _auth;
  final DateTime Function() _now;
  final _handlers = <OutboxKind, OutboxHandler>{};
  final _queued = StreamController<OutboxJob>.broadcast();

  /// Uploads made for an item that isn't queued (yet): its first try is
  /// still going. They move onto the job if it's queued.
  final _ready = <String, Map<int, ReadyUpload>>{};
  late final Future<void> _loaded;
  List<OutboxJob> _jobs = [];
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;
  Timer? _timer;
  bool _wasOnline = true;
  int _seenRecoveries = 0;

  /// Done once the saved queue is read.
  Future<void> get loaded => _loaded;

  String get _uid => _auth.currentUser?.uid ?? '';

  bool get online => _connectivity.online;

  /// Whether the device has a network (when offline, tells "no network"
  /// from "Stall 10 can't be reached").
  bool get hasNetwork => _connectivity.hasNetwork;

  /// The signed-in user's queued items, oldest first.
  List<OutboxJob> get jobs => [
    for (final j in _jobs)
      if (j.uid == _uid) j,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Items still to go out.
  int get waitingCount =>
      jobs.where((j) => j.state != OutboxState.failed).length;

  /// Items the server turned down.
  int get failedCount =>
      jobs.where((j) => j.state == OutboxState.failed).length;

  /// The user's queued items of [kind] for [target], oldest first.
  List<OutboxJob> jobsFor(OutboxKind kind, String target) => [
    for (final j in jobs)
      if (j.kind == kind && j.target == target) j,
  ];

  /// Each item queued (for a "will send when you're back" notice).
  Stream<OutboxJob> get queued => _queued.stream;

  @override
  Map<int, ReadyUpload> readyFor(String jobId) => Map.of(
    _jobs.where((j) => j.id == jobId).firstOrNull?.uploads ??
        _ready[jobId] ??
        const {},
  );

  @override
  Future<void> markReady(String jobId, int index, ReadyUpload upload) async {
    final job = _jobs.where((j) => j.id == jobId).firstOrNull;
    if (job == null) {
      (_ready[jobId] ??= {})[index] = upload;
      return;
    }
    _replace(job.copyWith(uploads: {...job.uploads, index: upload}));
    await _save();
  }

  /// Called by the repository that makes [kind].
  void register(OutboxKind kind, OutboxHandler handler) {
    _handlers[kind] = handler;
    unawaited(drain());
  }

  Future<void> _load() async {
    final saved = await _store.load();
    _jobs = [..._jobs, ...saved.where((s) => !_jobs.any((j) => j.id == s.id))];
    _notify();
    unawaited(drain());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _save() => _store.save(_jobs);

  void _onConnectivity() {
    final online = _connectivity.online;
    // Back online, or a check found the server fine after a failed send
    // (which queued that item without the app ever going offline).
    final recovered = _connectivity.recoveries != _seenRecoveries;
    _seenRecoveries = _connectivity.recoveries;
    if (online && (!_wasOnline || recovered)) unawaited(drain());
    _wasOnline = online;
    _notify();
  }

  void _onAuth() {
    _notify();
    unawaited(drain());
  }

  /// Sends now when Stall 10 can be reached, else (or when the send can't
  /// get through) queues it to go out later under the same [id]. Ok means
  /// sent or queued; an error means the server turned it down.
  Future<Result<void>> submit({
    required OutboxKind kind,
    required String id,
    required String target,
    required String label,
    required Map<String, Object?> payload,
    List<NewAttachment> files = const [],
    required Future<Result<void>> Function() sendNow,
  }) async {
    await _loaded;
    final uid = _uid;
    if (uid.isEmpty) return sendNow();
    try {
      return await _submit(
        uid: uid,
        kind: kind,
        id: id,
        target: target,
        label: label,
        payload: payload,
        files: files,
        sendNow: sendNow,
      );
    } finally {
      // Queued, the uploads are on the job; otherwise they're done with.
      _ready.remove(id);
    }
  }

  Future<Result<void>> _submit({
    required String uid,
    required OutboxKind kind,
    required String id,
    required String target,
    required String label,
    required Map<String, Object?> payload,
    required List<NewAttachment> files,
    required Future<Result<void>> Function() sendNow,
  }) async {
    Future<Result<void>> queue(OutboxFailure failure) => _enqueue(
      OutboxJob(
        id: id,
        uid: uid,
        kind: kind,
        createdAt: _now(),
        target: target,
        label: label,
        payload: Map<String, Object?>.from(jsonSafe(payload) as Map),
        uploads: Map.of(_ready[id] ?? const {}),
        // A server error waits before trying again.
        attempts: failure == OutboxFailure.retry ? 1 : 0,
        nextTryAt: failure == OutboxFailure.retry
            ? _now().add(outboxBackoff(0))
            : null,
      ),
      files,
    );
    if (!online) return queue(OutboxFailure.network);
    final Result<void> result;
    try {
      // Offline, a Firestore write waits instead of failing; uploads take
      // longer, so they get longer.
      result = await sendNow().timeout(
        files.isEmpty ? OutboxLimits.sendTimeout : const Duration(minutes: 2),
      );
    } on TimeoutException {
      _connectivity.reportFailure();
      return queue(OutboxFailure.network);
    }
    switch (result) {
      case Ok():
        _connectivity.reportOnline();
        return result;
      case Error(:final error):
        final failure = outboxFailureFor(error);
        switch (failure) {
          case OutboxFailure.network:
            _connectivity.reportFailure();
            return queue(failure);
          case OutboxFailure.retry:
            return queue(failure);
          case OutboxFailure.sent:
            return const Result.ok(null);
          case OutboxFailure.permanent:
            return result;
        }
    }
  }

  Future<Result<void>> _enqueue(
    OutboxJob job,
    List<NewAttachment> files,
  ) async {
    final mine = jobs;
    final bytes = files.fold(0, (n, f) => n + f.size);
    if (mine.length >= OutboxLimits.maxItems ||
        mine.fold(0, (n, j) => n + j.bytes) + bytes > OutboxLimits.maxBytes) {
      return Result.error(
        Exception(
          "You're offline and too much is already waiting to send. "
          'Try again once you have a connection.',
        ),
      );
    }
    try {
      // Fails here (not after the queue has changed) if it can't be saved.
      jsonEncode(job.toJson());
      final kept = [
        for (final (i, f) in files.indexed) await _store.putFile(job.id, i, f),
      ];
      final queued = OutboxJob(
        id: job.id,
        uid: job.uid,
        kind: job.kind,
        createdAt: job.createdAt,
        target: job.target,
        label: job.label,
        payload: job.payload,
        uploads: job.uploads,
        version: job.version,
        files: kept,
        attempts: job.attempts,
        nextTryAt: job.nextTryAt,
      );
      _jobs = [..._jobs.where((j) => j.id != job.id), queued];
      await _save();
      _notify();
      if (!_queued.isClosed) _queued.add(queued);
      _schedule();
      return const Result.ok(null);
    } catch (e) {
      _jobs = _jobs.where((j) => j.id != job.id).toList();
      await _store.deleteFiles(job.id).catchError((Object _) {});
      return Result.error(
        e is Exception ? e : Exception("Couldn't keep it to send later."),
      );
    }
  }

  void _replace(OutboxJob job) {
    _jobs = [
      for (final j in _jobs)
        if (j.id == job.id) job else j,
    ];
  }

  Future<void> _remove(OutboxJob job) async {
    _jobs = _jobs.where((j) => j.id != job.id).toList();
    await _store.deleteFiles(job.id).catchError((Object _) {});
  }

  /// Tries the failed item [id] again.
  Future<void> retry(String id) async {
    final job = _jobs.where((j) => j.id == id && j.uid == _uid).firstOrNull;
    if (job == null) return;
    _replace(
      job.copyWith(
        state: OutboxState.waiting,
        nextTryAt: () => null,
        error: () => null,
        // A try the server turned down may have refused its uploads (gone,
        // or made for something else): upload afresh.
        uploads: const {},
      ),
    );
    await _save();
    _notify();
    if (!online) unawaited(_connectivity.check());
    await drain();
  }

  /// Drops the item [id] without sending it.
  Future<void> discard(String id) async {
    final job = _jobs.where((j) => j.id == id && j.uid == _uid).firstOrNull;
    if (job == null || job.state == OutboxState.sending) return;
    await _remove(job);
    await _save();
    _notify();
  }

  /// Sends what's due, one at a time, until the queue is empty, the
  /// connection drops or the rest must wait for their next try. Called
  /// while a run is going, it runs again after it (something may have
  /// changed) and completes when that's done.
  Future<void> drain() {
    if (_disposed) return Future.value();
    if (_running case final running?) {
      _again = true;
      return running;
    }
    return _running = _drainLoop().whenComplete(() => _running = null);
  }

  Future<void> _drainLoop() async {
    try {
      await _loaded;
      do {
        _again = false;
        while (!_disposed && online) {
          final uid = _uid;
          final author = _auth.currentUser;
          if (uid.isEmpty || author == null) break;
          final due = dueJobs(
            _jobs,
            uid,
            _now(),
          ).where((j) => _handlers.containsKey(j.kind)).toList();
          if (due.isEmpty) break;
          if (!await _try(due.first, author)) break;
        }
      } while (_again && !_disposed);
    } finally {
      _schedule();
    }
  }

  /// One try at [job]; false when the connection's gone and the rest
  /// should wait.
  Future<bool> _try(OutboxJob job, AppUser author) async {
    final handler = _handlers[job.kind]!;
    _replace(job.copyWith(state: OutboxState.sending));
    _notify();
    OutboxFailure? failure;
    String? message;
    try {
      if (await handler.sent(job)) {
        failure = OutboxFailure.sent;
      } else {
        final files = [
          for (final f in job.files)
            NewAttachment(name: f.name, bytes: await _store.readFile(f)),
        ];
        final r = await handler
            .send(job, files, author)
            .timeout(
              files.isEmpty
                  ? OutboxLimits.sendTimeout
                  : const Duration(minutes: 2),
            );
        if (r case Error(:final error)) {
          failure = outboxFailureFor(error);
          message = _messageOf(error);
        }
      }
      // Turned down: maybe an earlier try (or Firestore's own pending
      // write) got there first, and this was the second copy.
      if (failure == OutboxFailure.permanent && await handler.sent(job)) {
        failure = OutboxFailure.sent;
      }
    } catch (e) {
      // Anything thrown, so the item never stays stuck as "Sending…".
      failure = outboxFailureFor(e);
      message = _messageOf(e);
    }
    // The uploads noted while sending are on the saved copy.
    final next = afterTry(
      _jobs.where((j) => j.id == job.id).firstOrNull ?? job,
      failure,
      _now(),
      message: message,
    );
    if (next == null) {
      await _remove(job);
    } else {
      _replace(next);
    }
    await _save();
    _notify();
    if (failure == OutboxFailure.network) {
      _connectivity.reportFailure();
      return false;
    }
    if (failure == null || failure == OutboxFailure.sent) {
      _connectivity.reportOnline();
    }
    return true;
  }

  /// Wakes up for the next item waiting out its backoff.
  void _schedule() {
    _timer?.cancel();
    if (_disposed) return;
    final next = jobs
        .where((j) => j.state == OutboxState.waiting && j.nextTryAt != null)
        .map((j) => j.nextTryAt!)
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    if (next == null) return;
    final wait = next.difference(_now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      unawaited(drain());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _connectivity.removeListener(_onConnectivity);
    _auth.removeListener(_onAuth);
    unawaited(_queued.close());
    super.dispose();
  }
}
