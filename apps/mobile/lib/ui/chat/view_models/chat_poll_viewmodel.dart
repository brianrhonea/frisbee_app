import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/chat/chat_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Backs one poll card in a team room (redesign F33): the live poll (the
/// card listens to its own message, since older pages of a thread aren't
/// live), the viewer's choice, voting and closing early. Votes and closing
/// go through the API.
class ChatPollCardViewModel extends ChangeNotifier {
  ChatPollCardViewModel({
    required this.teamId,
    required this.roomId,
    required ChatMessage message,
    required ChatRepository chatRepository,
    required AuthRepository authRepository,
    required bool Function() canManage,
    String Function(String uid)? nameOf,
    DateTime Function()? now,
  }) : _chats = chatRepository,
       _auth = authRepository,
       _message = message,
       _canManage = canManage,
       _nameOf = nameOf ?? ((_) => 'Member'),
       _now = now ?? DateTime.now {
    vote = Command1<void, List<int>>(_vote);
    close = Command0<void>(() => _chats.closePoll(teamId, roomId, _message.id));
    _sub = _chats.watchMessage(teamId, roomId, message.id).listen(
      (m) {
        if (m == null) {
          _deleted = true;
        } else {
          _message = m;
        }
        // The vote being sent has landed (or someone else's change has).
        _sending = null;
        notifyListeners();
      },
      // Keeps what the thread gave it.
      onError: (Object _) {},
    );
  }

  final String teamId;
  final String roomId;

  /// Whether the viewer may close anyone's poll (the owner and chat
  /// managers), asked each time: their roles can change while it's open.
  final bool Function() _canManage;

  final ChatRepository _chats;
  final AuthRepository _auth;
  final String Function(String uid) _nameOf;
  final DateTime Function() _now;
  late final StreamSubscription<ChatMessage?> _sub;

  ChatMessage _message;
  bool _deleted = false;

  /// The choice being sent, shown until the poll's next update.
  List<int>? _sending;

  String get uid => _auth.currentUser?.uid ?? '';

  ChatPoll? get poll => _deleted ? null : _message.poll;

  /// The message was deleted (and its poll with it).
  bool get deleted => _deleted;

  /// Whether this build can vote and close (it talks to the API).
  bool get online => _chats.canUseChatExtras;

  /// The viewer's choice: what they're sending, else what's stored.
  List<int> get mine => _sending ?? poll?.picksOf(uid) ?? const [];

  bool get isClosed => poll?.isClosed(_now()) ?? true;

  bool get canVote => online && !isClosed;

  /// Amber "Vote": open, and the viewer hasn't voted yet.
  bool get needsVote => canVote && mine.isEmpty;

  /// Its author, or the room's chat managers, close it early.
  bool get canClose =>
      online && !isClosed && (_message.authorId == uid || _canManage());

  /// Votes per option, counting the viewer's choice as sent.
  List<int> get counts {
    final p = poll;
    if (p == null) return const [];
    final counts = List.of(p.counts);
    if (_sending case final next?) {
      for (final i in p.picksOf(uid)) {
        counts[i]--;
      }
      for (final i in next) {
        counts[i]++;
      }
    }
    return counts;
  }

  /// How many people voted, counting the viewer's choice as sent.
  int get voterCount {
    final p = poll;
    if (p == null) return 0;
    final before = p.picksOf(uid).isNotEmpty ? 1 : 0;
    final after = mine.isNotEmpty ? 1 : 0;
    return p.voterCount - before + after;
  }

  /// "Closes Fri 5:00 PM"-style end, or null without one.
  DateTime? get closesAt => poll?.closesAt;

  /// The names of who picked option [i], sorted (same visibility as the room).
  List<String> votersFor(int i) =>
      [for (final u in poll?.votersFor(i) ?? const <String>[]) _nameOf(u)]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Sets or sends the viewer's whole choice.
  late final Command1<void, List<int>> vote;

  /// Closes the poll early.
  late final Command0<void> close;

  /// Taps option [i]: picks it, takes it back, or (single choice) swaps.
  void tap(int i) {
    final p = poll;
    if (p == null || !canVote || vote.running) return;
    vote.execute(p.toggle(mine, i));
  }

  Future<Result<void>> _vote(List<int> options) async {
    _sending = options;
    notifyListeners();
    final result = await _chats.votePoll(teamId, roomId, _message.id, options);
    // On success the choice stays shown until the poll's next update
    // brings it back (unless it already has), so it doesn't flash back.
    if (result is Error || listEquals(poll?.picksOf(uid), options)) {
      _sending = null;
    }
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _sub.cancel();
    vote.dispose();
    close.dispose();
    super.dispose();
  }
}

/// One option being written in the new-poll form; [id] keeps its field
/// when others are removed.
typedef PollOptionDraft = ({int id, String text});

/// Backs "Poll" in a team room's attach menu (redesign F33): a question,
/// 2–6 options, "Allow multiple answers" and an optional closing time,
/// checked as the API checks them.
class ChatPollFormViewModel extends ChangeNotifier {
  ChatPollFormViewModel({
    required this.teamId,
    required this.roomId,
    required ChatRepository chatRepository,
    DateTime Function()? now,
  }) : _chats = chatRepository,
       _now = now ?? DateTime.now {
    submit = Command0<void>(_submit);
  }

  final String teamId;
  final String roomId;
  final ChatRepository _chats;
  final DateTime Function() _now;

  String _question = '';
  var _nextId = 2;
  List<PollOptionDraft> _options = const [(id: 0, text: ''), (id: 1, text: '')];
  bool _multiple = false;
  DateTime? _closesAt;

  String get question => _question;
  List<PollOptionDraft> get options => _options;
  bool get multiple => _multiple;
  DateTime? get closesAt => _closesAt;

  bool get canAddOption => _options.length < chatPollOptionsMax;
  bool get canRemoveOption => _options.length > chatPollOptionsMin;

  void setQuestion(String v) {
    _question = v;
    notifyListeners();
  }

  void setOption(int id, String v) {
    _options = [for (final o in _options) o.id == id ? (id: id, text: v) : o];
    notifyListeners();
  }

  void addOption() {
    if (!canAddOption) return;
    _options = [..._options, (id: _nextId++, text: '')];
    notifyListeners();
  }

  void removeOption(int id) {
    if (!canRemoveOption) return;
    _options = [..._options.where((o) => o.id != id)];
    notifyListeners();
  }

  void setMultiple(bool v) {
    _multiple = v;
    notifyListeners();
  }

  /// Null: open until someone closes it.
  void setClosesAt(DateTime? v) {
    _closesAt = v;
    notifyListeners();
  }

  /// What stops it being posted, or null when it's ready.
  String? get problem {
    if (_question.trim().isEmpty) return 'Ask a question.';
    if (_question.trim().length > chatPollQuestionMax) {
      return 'Keep the question under $chatPollQuestionMax characters.';
    }
    final texts = [for (final o in _options) o.text.trim()];
    if (texts.any((t) => t.isEmpty)) {
      return 'Fill in every option, or remove it.';
    }
    if (texts.any((t) => t.length > chatPollOptionMax)) {
      return 'Keep each option under $chatPollOptionMax characters.';
    }
    if ({for (final t in texts) t.toLowerCase()}.length != texts.length) {
      return 'Each option must be different.';
    }
    if (_closesAt case final at? when !at.isAfter(_now())) {
      return 'Pick a closing time in the future.';
    }
    return null;
  }

  bool get canSubmit => problem == null && !submit.running;

  /// Posts the poll.
  late final Command0<void> submit;

  Future<Result<void>> _submit() {
    if (problem case final p?) return Future.value(Result.error(Exception(p)));
    return _chats.createPoll(teamId, roomId, (
      question: _question.trim(),
      options: [for (final o in _options) o.text.trim()],
      multiple: _multiple,
      closesAt: _closesAt,
    ));
  }

  @override
  void dispose() {
    submit.dispose();
    super.dispose();
  }
}
