import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/people/people_repository.dart';
import '../../../data/services/file_picker_service.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../utils/command.dart';
import '../../../utils/pending_removals.dart';
import '../../../utils/result.dart';

/// A list of messages with a composer: shared by team chat rooms and
/// direct messages. Subclasses say where messages come from and go.
abstract class MessageThreadViewModel extends ChangeNotifier {
  MessageThreadViewModel({
    required AuthRepository authRepository,
    required FilePickerService filePicker,
    PeopleRepository? peopleRepository,
    NotificationRepository? notificationRepository,
  }) : _auth = authRepository,
       _picker = filePicker,
       _people = peopleRepository,
       _notices = notificationRepository {
    if (notificationRepository != null) {
      _lifecycle = _tryLifecycleListener(_markSeen);
    }
    send = Command1<void, String>(_send);
    pickFiles = Command1<void, bool>(_pickFiles);
    deleteMessage = Command1<void, ChatMessage>(_delete);
    saveAttachment = Command1<bool, ChatAttachment>(_saveAttachment);
  }

  static const pageSize = 50;

  final AuthRepository _auth;
  final FilePickerService _picker;
  final PeopleRepository? _people;
  final NotificationRepository? _notices;
  AppLifecycleListener? _lifecycle;

  /// The newest message from someone else already marked seen.
  String? _seenUpTo;
  StreamSubscription<List<ChatMessage>>? _messageSub;

  /// Sends the composer's text with the pending attachments.
  late final Command1<void, String> send;

  /// Adds files to the pending attachments; true picks photos only.
  late final Command1<void, bool> pickFiles;
  late final Command1<void, ChatMessage> deleteMessage;

  /// Messages deleted, hidden while "Undo" is offered.
  late final removals = PendingRemovals<ChatMessage>(
    keyOf: (m) => m.id,
    commit: deleteMessage.execute,
    onChange: notifyListeners,
  );

  /// Downloads an attachment and asks where to save it. False if cancelled.
  late final Command1<bool, ChatAttachment> saveAttachment;

  /// The newest [pageSize] messages, live.
  List<ChatMessage>? _live;

  /// Older messages: pages loaded with [loadMore], plus ones new messages
  /// pushed out of the live page. Oldest first.
  final _older = <ChatMessage>[];
  bool _olderExhausted = false;
  bool _loadingMore = false;
  bool _pagingFailed = false;

  /// Grows when cursor paging fails, as the fallback.
  int _limit = pageSize;
  Object? _messageError;
  final _drafts = <NewAttachment>[];
  final _downloads = <String, Future<Result<Uint8List>>>{};

  // Where messages come from and go.
  @protected
  Stream<List<ChatMessage>> watchMessages(int limit);

  /// Up to [limit] messages older than [before], oldest first.
  @protected
  Future<Result<List<ChatMessage>>> fetchOlder(ChatMessage before, int limit);
  @protected
  Future<Result<void>> postMessage(
    AppUser author,
    String text,
    List<NewAttachment> attachments,
  );
  @protected
  Future<Result<void>> removeMessage(ChatMessage message);
  @protected
  Future<Result<Uint8List>> download(ChatAttachment attachment);

  bool get canWrite;

  /// A small note under [message], e.g. "Seen"; null for none.
  String? receiptFor(ChatMessage message) => null;

  /// Whether messages can carry photos and files.
  bool get canAttach => true;

  /// The color (0xAARRGGBB) to show [uid]'s name in, from their top
  /// colored role, or null for the default.
  int? nameColorOf(String uid) => null;

  /// [uid]'s username, without the "@", once looked up; null if they
  /// have none or it hasn't arrived yet.
  String? usernameOf(String uid) => _people?.cached(uid)?.username;

  /// Looks up the usernames of [uids] not yet known, then redraws.
  @protected
  void lookUpPeople(Iterable<String> uids) {
    final people = _people;
    if (people == null) return;
    for (final id in uids.toSet()) {
      if (id.isEmpty || people.cached(id) != null) continue;
      people.person(id).then((p) {
        if (p?.username != null && !_disposed) notifyListeners();
      });
    }
  }

  bool _disposed = false;

  // Typing ------------------------------------------------------------------

  /// How often, at most, the user's typing is sent while they type.
  static const typingEvery = Duration(seconds: 3);

  /// How long someone counts as typing after their last keystroke shows.
  static const typingFor = Duration(seconds: 6);

  /// Whether this thread shows who's typing.
  bool get showsTyping => false;

  /// Where others' typing comes from; null where it isn't shown.
  @protected
  Stream<Map<String, DateTime?>>? watchTyping() => null;

  /// Tells the others the user is typing, or has stopped.
  @protected
  Future<void> sendTyping({required bool typing}) async {}

  /// The name to show for [uid] when they're typing.
  @protected
  String typistName(String uid) => _people?.cached(uid)?.name ?? 'Someone';

  StreamSubscription<Map<String, DateTime?>>? _typingSub;
  Map<String, DateTime?> _typingSeen = const {};

  /// uid → when (on this device's clock) they stop counting as typing.
  final _typingUntil = <String, DateTime>{};
  Timer? _typingExpiry;
  DateTime? _sentTypingAt;

  /// Clock, replaceable in tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// Starts showing who's typing; call from the subclass constructor.
  @protected
  void startTyping() {
    _typingSub?.cancel();
    _typingSub = watchTyping()?.listen(_onTyping, onError: (Object _) {});
  }

  void _onTyping(Map<String, DateTime?> typing) {
    final at = now();
    for (final MapEntry(key: id, value: stamp) in typing.entries) {
      if (id == uid) continue;
      // A new or rewritten entry: they've just typed. The server's time
      // only says it changed, so a skewed clock can't hide or stick it.
      if (!_typingSeen.containsKey(id) || _typingSeen[id] != stamp) {
        _typingUntil[id] = at.add(typingFor);
      }
    }
    _typingUntil.removeWhere((id, _) => !typing.containsKey(id));
    _typingSeen = typing;
    _scheduleTypingExpiry();
    notifyListeners();
  }

  void _scheduleTypingExpiry() {
    _typingExpiry?.cancel();
    if (_typingUntil.isEmpty) return;
    final next = _typingUntil.values.reduce((a, b) => a.isBefore(b) ? a : b);
    var wait = next.difference(now());
    if (wait.isNegative) wait = Duration.zero;
    _typingExpiry = Timer(wait + const Duration(milliseconds: 50), () {
      if (_disposed) return;
      final at = now();
      _typingUntil.removeWhere((_, until) => !until.isAfter(at));
      _scheduleTypingExpiry();
      notifyListeners();
    });
  }

  /// Others typing right now, oldest typist first.
  List<String> get typingNames {
    final at = now();
    return [
      for (final MapEntry(key: id, value: until) in _typingUntil.entries)
        if (until.isAfter(at)) typistName(id),
    ];
  }

  /// "Avery is typing…", "Avery and Blake are typing…", or null.
  String? get typingLabel => switch (typingNames) {
    [] => null,
    [final a] => '$a is typing…',
    [final a, final b] => '$a and $b are typing…',
    [final a, ...final rest] => '$a and ${rest.length} others are typing…',
  };

  /// The composer's text changed: tells the others, at most every
  /// [typingEvery], and that the user stopped once it's empty.
  void composerChanged(String text) {
    if (!canWrite) return;
    final at = now();
    if (text.trim().isEmpty) {
      if (_sentTypingAt != null) {
        _sentTypingAt = null;
        sendTyping(typing: false);
      }
      return;
    }
    final last = _sentTypingAt;
    if (last != null && at.difference(last) < typingEvery) return;
    _sentTypingAt = at;
    sendTyping(typing: true);
  }

  /// The collapse id of this thread's notifications (see
  /// functions/src/notifications/model.ts), cleared once its messages
  /// are on screen; null for none.
  @protected
  String? get noticeKey => null;

  /// Clears this thread's notification once its newest message from
  /// someone else has been on screen with the app in the foreground.
  void _markSeen() {
    final notices = _notices;
    final key = noticeKey;
    final live = _live;
    if (notices == null || key == null || live == null || _disposed) return;
    if (!_inForeground()) return;
    final newest = live.lastWhere(
      (m) => m.authorId != uid,
      orElse: () => const ChatMessage(id: '', authorId: '', authorName: ''),
    );
    // The first time, clear even with nothing new: it was read elsewhere.
    if (_seenUpTo != null && newest.id == _seenUpTo) return;
    _seenUpTo = newest.id;
    notices.markSeen(uid, key);
  }

  static bool _inForeground() {
    try {
      final s = WidgetsBinding.instance.lifecycleState;
      return s == null || s == AppLifecycleState.resumed;
    } on Object {
      return true;
    }
  }

  static AppLifecycleListener? _tryLifecycleListener(VoidCallback onResume) {
    try {
      return AppLifecycleListener(onResume: onResume);
    } on Object {
      // No binding (a plain unit test).
      return null;
    }
  }

  /// Who may delete [m] besides its author.
  @protected
  bool get canModerate => false;

  /// Called whenever a new page of messages arrives.
  @protected
  void onMessages(List<ChatMessage> messages) {}

  String get uid => _auth.currentUser?.uid ?? '';
  List<ChatMessage> get messages => removals.visible([..._older, ...?_live]);
  bool get messagesLoaded => _live != null;
  Object? get messageError => _messageError;

  /// More messages may be on the server than those loaded.
  bool get hasMore => !_olderExhausted && (_live?.length ?? 0) >= _limit;

  /// Whether an older page is on its way.
  bool get loadingMore => _loadingMore;

  /// Whether scrolling to the top should load the next page by itself.
  /// Off once paging has failed, so a broken query can't loop.
  bool get autoLoadMore => !_pagingFailed && !_loadingMore;

  /// Pending attachments for the next message.
  List<NewAttachment> get drafts => List.unmodifiable(_drafts);

  bool isMine(ChatMessage m) => m.authorId == uid;

  bool canDelete(ChatMessage m) => isMine(m) || canModerate;

  /// Starts (or restarts) listening; call from the subclass constructor.
  @protected
  void startMessages() {
    _messageSub?.cancel();
    _messageSub = watchMessages(_limit).listen((m) {
      _keepPushedOut(_live, m);
      // A deletion pulls an older message back into the live page.
      final live = {for (final x in m) x.id};
      _older.removeWhere((x) => live.contains(x.id));
      _live = m;
      _messageError = null;
      lookUpPeople(m.map((x) => x.authorId));
      onMessages(m);
      _markSeen();
      notifyListeners();
    }, onError: _onMessageError);
  }

  /// A new message pushes the oldest out of the live page; keep it (with
  /// the older pages) unless it was deleted. A pushed-out message is older
  /// than everything still in a full page; a deleted one isn't, or the
  /// page wasn't full.
  void _keepPushedOut(List<ChatMessage>? before, List<ChatMessage> after) {
    if (before == null || after.isEmpty || after.length < _limit) return;
    final oldest = after.first.createdAt;
    if (oldest == null) return;
    final ids = {for (final m in after) m.id};
    final pushed = [
      for (final m in before)
        if (!ids.contains(m.id) &&
            m.createdAt != null &&
            m.createdAt!.isBefore(oldest))
          m,
    ];
    if (pushed.isEmpty) return;
    final known = {for (final m in _older) m.id};
    _older.addAll(pushed.where((m) => !known.contains(m.id)));
  }

  void _onMessageError(Object e) {
    _messageError = e;
    _live ??= const [];
    notifyListeners();
  }

  /// Loads the page of messages above those shown. Reads only that page;
  /// if paging fails it falls back to listening to a bigger live page.
  Future<void> loadMore() async {
    final live = _live;
    if (_loadingMore || live == null || !hasMore) return;
    final before = _older.firstOrNull ?? live.firstOrNull;
    if (before == null) return;
    if (_pagingFailed) {
      _limit += pageSize;
      startMessages();
      return;
    }
    _loadingMore = true;
    notifyListeners();
    final result = await fetchOlder(before, pageSize);
    _loadingMore = false;
    switch (result) {
      case Ok(:final value):
        final known = {for (final m in _older) m.id};
        _older.insertAll(0, value.where((m) => !known.contains(m.id)));
        lookUpPeople(value.map((x) => x.authorId));
        if (value.length < pageSize) _olderExhausted = true;
        notifyListeners();
      case Error():
        _pagingFailed = true;
        _older.clear();
        _limit += pageSize;
        startMessages();
    }
  }

  void removeDraft(NewAttachment a) {
    _drafts.remove(a);
    notifyListeners();
  }

  /// Attachment bytes, fetched once per attachment.
  Future<Result<Uint8List>> attachmentData(ChatAttachment a) =>
      _downloads[a.path] ??= download(a).then((r) {
        if (r is Error) _downloads.remove(a.path);
        return r;
      });

  Future<Result<void>> _delete(ChatMessage m) async {
    final result = await removeMessage(m);
    if (result is Ok) {
      final before = _older.length;
      _older.removeWhere((o) => o.id == m.id);
      if (_older.length != before) notifyListeners();
    }
    return result;
  }

  Future<Result<void>> _send(String text) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    if (text.trim().isEmpty && _drafts.isEmpty) return const Result.ok(null);
    final attachments = List.of(_drafts);
    final result = await postMessage(user, text, attachments);
    if (_sentTypingAt != null) {
      _sentTypingAt = null;
      unawaited(sendTyping(typing: false));
    }
    if (result is Ok) {
      _drafts.removeWhere(attachments.contains);
      notifyListeners();
    }
    return result;
  }

  Future<Result<void>> _pickFiles(bool imagesOnly) async {
    final List<PickedFile> picked;
    try {
      picked = await _picker.pick(imagesOnly: imagesOnly);
    } on Exception catch (e) {
      return Result.error(e);
    }
    final tooLarge = <String>[];
    for (final f in picked) {
      final a = await readAttachment(_picker, f);
      if (a == null || a.tooLarge) {
        tooLarge.add(f.name);
      } else {
        _drafts.add(a);
      }
    }
    notifyListeners();
    if (tooLarge.isNotEmpty) {
      return Result.error(AttachmentTooLargeException(tooLarge.join(', ')));
    }
    return const Result.ok(null);
  }

  Future<Result<bool>> _saveAttachment(ChatAttachment a) async {
    final data = await attachmentData(a);
    switch (data) {
      case Error(:final error):
        return Result.error(error);
      case Ok(:final value):
        try {
          return Result.ok(await _picker.save(a.name, value, a.contentType));
        } on Exception catch (e) {
          return Result.error(e);
        }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _typingSub?.cancel();
    _typingExpiry?.cancel();
    if (_sentTypingAt != null) unawaited(sendTyping(typing: false));
    _lifecycle?.dispose();
    removals.flush(removeMessage);
    _messageSub?.cancel();
    super.dispose();
  }
}
