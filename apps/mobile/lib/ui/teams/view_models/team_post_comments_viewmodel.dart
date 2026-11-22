import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/team_post/team_post_repository.dart';
import '../../../domain/models/team_post.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// A team post's comment thread (redesign F24): oldest first, live. Any
/// member comments; its author or a team admin ([canModerate]) deletes a
/// comment. Writes go through the API.
class TeamPostCommentsViewModel extends ChangeNotifier {
  TeamPostCommentsViewModel({
    required this.teamId,
    required this.postId,
    required TeamPostRepository repository,
    required this.uid,
    required this.canModerate,
  }) : _repo = repository {
    add = Command1<void, String>(_add);
    delete = Command1<void, String>(
      (id) => _repo.deleteComment(teamId, postId, id),
    );
    _sub = _repo
        .watchComments(teamId, postId)
        .listen(
          (c) {
            _comments = c;
            _error = null;
            _loaded = true;
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loaded = true;
            notifyListeners();
          },
        );
  }

  final String teamId;
  final String postId;
  final String uid;

  /// A team admin: deletes anyone's comment.
  final bool canModerate;
  final TeamPostRepository _repo;
  late final StreamSubscription<List<TeamPostComment>> _sub;

  List<TeamPostComment> _comments = const [];
  bool _loaded = false;
  Object? _error;

  List<TeamPostComment> get comments => _comments;
  bool get loaded => _loaded;
  Object? get error => _error;

  /// Whether the API is there to write comments.
  bool get canWrite => _repo.canUseFeedExtras;

  bool canDelete(TeamPostComment c) =>
      canWrite && (c.authorId == uid || canModerate);

  /// Posts [body] (trimmed); empty or too long is refused here first.
  late final Command1<void, String> add;
  late final Command1<void, String> delete;

  Future<Result<void>> _add(String body) {
    final text = body.trim();
    if (text.isEmpty) {
      return Future.value(Result.error(Exception('Write a comment first.')));
    }
    if (text.length > TeamPostComment.maxLength) {
      return Future.value(
        Result.error(
          Exception('Keep it under ${TeamPostComment.maxLength} characters.'),
        ),
      );
    }
    return _repo.addComment(teamId, postId, text);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
