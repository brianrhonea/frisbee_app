import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// One person's post on its own page, where post notifications lead.
class PostDetailViewModel extends ChangeNotifier {
  PostDetailViewModel({
    required this.postId,
    required UserPostRepository userPostRepository,
    required AuthRepository authRepository,
  }) : _posts = userPostRepository,
       _auth = authRepository {
    delete = Command0<void>(() => _posts.deletePost(postId));
    _sub = _posts
        .watchPost(postId)
        .listen(
          (p) {
            _post = p;
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

  final String postId;
  final UserPostRepository _posts;
  final AuthRepository _auth;
  late final StreamSubscription<UserPost?> _sub;
  final _downloads = <String, Future<Result<Uint8List>>>{};

  UserPost? _post;
  bool _loaded = false;
  Object? _error;

  UserPost? get post => _post;
  bool get loaded => _loaded;
  Object? get error => _error;
  bool get isMine => _post != null && _post!.authorId == _auth.currentUser?.uid;

  late final Command0<void> delete;

  Future<Result<Uint8List>> imageData(ChatAttachment image) =>
      _downloads[image.path] ??= _posts.downloadImage(image).then((r) {
        if (r is Error) _downloads.remove(image.path);
        return r;
      });

  @override
  void dispose() {
    _sub.cancel();
    delete.dispose();
    super.dispose();
  }
}
