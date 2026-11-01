import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../data/services/file_picker_service.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../teams/view_models/team_home_viewmodel.dart' show pickPostImages;

/// Writes a new post or workout, or edits [postId].
class PostComposerViewModel extends ChangeNotifier {
  PostComposerViewModel({
    this.postId,
    this.startWithWorkout = false,
    required UserPostRepository userPostRepository,
    required FollowRepository followRepository,
    required AuthRepository authRepository,
    required FilePickerService filePicker,
  }) : _posts = userPostRepository,
       _auth = authRepository,
       _picker = filePicker {
    save = Command1<String, UserPostDraft>(_save);
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      _subs.add(
        followRepository.watchFollows(uid).listen((f) {
          _tournaments = [
            for (final x in f)
              if (x.type == FollowType.tournament || x.type == FollowType.event)
                x.target,
          ];
          notifyListeners();
        }, onError: (Object _) {}),
      );
    }
    final id = postId;
    if (id == null) {
      _loaded = true;
    } else {
      _subs.add(
        _posts
            .watchPost(id)
            .listen(
              (p) {
                // Keep the first copy; the form owns the edits from there.
                if (_loaded) return;
                _initial = p;
                _loaded = true;
                notifyListeners();
              },
              onError: (Object e) {
                _loadError = e;
                _loaded = true;
                notifyListeners();
              },
            ),
      );
    }
  }

  final String? postId;

  /// Open on the Workout tab.
  final bool startWithWorkout;
  final UserPostRepository _posts;
  final AuthRepository _auth;
  final FilePickerService _picker;
  final List<StreamSubscription<Object?>> _subs = [];
  final _downloads = <String, Future<Result<Uint8List>>>{};

  bool _loaded = false;
  Object? _loadError;
  UserPost? _initial;
  List<FollowTarget> _tournaments = const [];

  bool get isNew => postId == null;
  bool get loaded => _loaded;
  Object? get loadError => _loadError;

  /// The post being edited; null for a new one or when it's gone.
  UserPost? get initial => _initial;

  /// Whether the user may edit it: their own post, still there.
  bool get canEdit =>
      isNew ||
      (_initial != null && _initial!.authorId == _auth.currentUser?.uid);

  /// Tournaments and events the user follows, to tag the post with.
  List<FollowTarget> get tournaments => _tournaments;

  /// Saves; the result is the post id.
  late final Command1<String, UserPostDraft> save;

  Future<Result<String>> _save(UserPostDraft draft) async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    final post = draft.post;
    if (post.workout case final w? when !w.isValid) {
      return Result.error(Exception(w.problem));
    }
    if (!post.hasContent && draft.newImages.isEmpty) {
      return Result.error(Exception('Write something or add a photo'));
    }
    return _posts.savePost(draft, me);
  }

  Future<Result<List<NewAttachment>>> pickImages() => pickPostImages(_picker);

  Future<Result<Uint8List>> imageData(ChatAttachment image) =>
      _downloads[image.path] ??= _posts.downloadImage(image).then((r) {
        if (r is Error) _downloads.remove(image.path);
        return r;
      });

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    save.dispose();
    super.dispose();
  }
}
