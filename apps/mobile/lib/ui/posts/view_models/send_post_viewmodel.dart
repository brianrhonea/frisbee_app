import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../../utils/invite_links.dart';
import '../../../utils/result.dart';
import '../../core/ui/brand.dart';

/// Sends a post to people as a direct message: a line about it and its
/// link, which opens the post in the app. People the user has talked to
/// are listed first; anyone else is found by name.
class SendPostViewModel extends ChangeNotifier {
  SendPostViewModel({
    required this.post,
    required DirectMessageRepository directMessageRepository,
    required AuthRepository authRepository,
    this.debounce = const Duration(milliseconds: 300),
  }) : _dms = directMessageRepository,
       _auth = authRepository {
    send = Command1<void, UserProfile>(_send);
    final uid = _uid;
    if (uid.isNotEmpty) {
      _convSub = _dms
          .watchConversations(uid)
          .listen(
            (c) {
              _recent = [
                for (final x in c)
                  if (x.otherId(uid) != uid)
                    UserProfile(uid: x.otherId(uid), name: x.otherName(uid)),
              ];
              notifyListeners();
            },
            onError: (Object _) {
              _recent = const [];
              notifyListeners();
            },
          );
    }
  }

  static const minQueryLength = 2;

  /// The post to send: a repost's original, so the link shows the post
  /// itself.
  final UserPost post;
  final DirectMessageRepository _dms;
  final AuthRepository _auth;
  final Duration debounce;

  StreamSubscription<List<Conversation>>? _convSub;
  Timer? _timer;
  int _searchId = 0;

  String get _uid => _auth.currentUser?.uid ?? '';

  /// Sends [post] to a person, in their conversation with the user.
  late final Command1<void, UserProfile> send;

  List<UserProfile>? _recent;

  /// People the user has messaged, most recent first; null while loading.
  List<UserProfile>? get recent => _recent;

  String _query = '';
  String get query => _query;

  List<UserProfile> _results = const [];
  List<UserProfile> get results => _results;

  bool _searching = false;
  bool get searching => _searching;

  Object? _searchError;
  Object? get searchError => _searchError;

  final Set<String> _sent = {};
  final Set<String> _sending = {};

  bool wasSent(String uid) => _sent.contains(uid);
  bool isSending(String uid) => _sending.contains(uid);

  /// The post's link, for messages and other apps.
  Uri get link => InviteLinks.post(post.id);

  /// What's sent: who posted, a taste of it, and the link.
  String get messageText {
    final whose = post.authorId == _uid
        ? 'my post'
        : post.authorName.isEmpty
        ? 'this post'
        : "${post.authorName}'s post";
    final preview = postPreviewText(post);
    return [
      'Check out $whose on $appName',
      if (preview.isNotEmpty) ': “$preview”',
      '\n$link',
    ].join();
  }

  /// Searches for [query] once typing pauses.
  void search(String query) {
    _query = query.trim();
    _timer?.cancel();
    if (_query.length < minQueryLength) {
      _searchId++;
      _results = const [];
      _searching = false;
      _searchError = null;
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();
    _timer = Timer(debounce, _run);
  }

  Future<void> _run() async {
    final id = ++_searchId;
    final result = await _dms.searchPeople(_query, excludeUid: _uid);
    if (id != _searchId) return;
    _searching = false;
    switch (result) {
      case Ok(:final value):
        _results = value;
        _searchError = null;
      case Error(:final error):
        _results = const [];
        _searchError = error;
    }
    notifyListeners();
  }

  Future<Result<void>> _send(UserProfile person) async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    if (person.uid == me.uid) {
      return Result.error(Exception("You can't send a post to yourself"));
    }
    if (_sent.contains(person.uid) || _sending.contains(person.uid)) {
      return const Result.ok(null);
    }
    _sending.add(person.uid);
    notifyListeners();
    try {
      final convo = await _dms.openConversation(me, person);
      final Result<void> result = switch (convo) {
        Ok(:final value) => await _dms.sendMessage(
          value,
          author: me,
          text: messageText,
        ),
        Error(:final error) => Result.error(error),
      };
      if (result is Ok) _sent.add(person.uid);
      return result;
    } finally {
      _sending.remove(person.uid);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _convSub?.cancel();
    send.dispose();
    super.dispose();
  }
}

/// A short taste of [post] for a message: its text, else the event or
/// workout it shares.
String postPreviewText(UserPost post) {
  final text = post.body.trim().replaceAll(RegExp(r'\s+'), ' ');
  final s = text.isNotEmpty
      ? text
      : post.event?.title ?? post.workout?.activity.label ?? '';
  return s.length > 80 ? '${s.substring(0, 77)}…' : s;
}
