import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/profile/profile_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../follow/view_models/follow_viewmodel.dart';

/// A person's public page: name, photo, follow counts and their posts.
class UserProfileViewModel extends ChangeNotifier {
  UserProfileViewModel({
    required this.uid,
    required ProfileRepository profileRepository,
    required UserPostRepository userPostRepository,
    required FollowRepository followRepository,
    required DirectMessageRepository directMessageRepository,
    required AuthRepository authRepository,
    NotificationRepository? notificationRepository,
  }) : _posts = userPostRepository,
       _messages = directMessageRepository,
       _auth = authRepository,
       _followSlot = FollowSlot(
         followRepository: followRepository,
         notificationRepository: notificationRepository,
         authRepository: authRepository,
       ) {
    message = Command0<String>(_message);
    deletePost = Command1<void, String>(_posts.deletePost);
    _subs
      ..add(
        profileRepository
            .watchProfile(uid)
            .listen(
              (p) {
                _profile = p;
                _profileLoaded = true;
                notifyListeners();
              },
              onError: (Object _) {
                _profileLoaded = true;
                notifyListeners();
              },
            ),
      )
      ..add(
        _posts
            .watchPostsBy(uid)
            .listen(
              (p) {
                _postList = p;
                _postsLoaded = true;
                notifyListeners();
              },
              onError: (Object e) {
                _postsError = e;
                _postsLoaded = true;
                notifyListeners();
              },
            ),
      )
      ..add(
        followRepository.watchCounts(FollowTarget.userKey(uid)).listen((c) {
          _counts = c;
          notifyListeners();
        }, onError: (Object _) {}),
      );
  }

  final String uid;
  final UserPostRepository _posts;
  final DirectMessageRepository _messages;
  final AuthRepository _auth;
  final FollowSlot _followSlot;
  final List<StreamSubscription<Object?>> _subs = [];
  final _downloads = <String, Future<Result<Uint8List>>>{};

  UserProfile? _profile;
  bool _profileLoaded = false;
  List<UserPost> _postList = const [];
  bool _postsLoaded = false;
  Object? _postsError;
  FollowCounts _counts = const FollowCounts();

  bool get loaded => _profileLoaded;
  bool get postsLoaded => _postsLoaded;
  Object? get postsError => _postsError;

  bool get isMe => uid == _auth.currentUser?.uid;

  /// The public profile; for the signed-in user it falls back to their
  /// account, since the directory only lists people with a display name.
  UserProfile? get profile =>
      _profile ??
      switch (_auth.currentUser) {
        final me? when isMe => UserProfile(
          uid: me.uid,
          name: me.label,
          photoUrl: me.photoUrl,
        ),
        _ => null,
      };

  /// Their name, or a name from their posts if they have no profile.
  String get name =>
      profile?.name ?? _postList.firstOrNull?.authorName ?? 'Player';

  FollowTarget get target =>
      FollowTarget.user(uid, name, photoUrl: profile?.photoUrl);

  /// The Follow button; null on your own profile, and until it loads.
  FollowViewModel? get follow =>
      isMe || !loaded ? null : _followSlot.of(target);

  List<UserPost> get posts => _postList;
  int get followers => _counts.followers;
  int get following => _counts.following;

  /// Opens a direct-message conversation; the result is its id.
  late final Command0<String> message;
  late final Command1<void, String> deletePost;

  Future<Result<String>> _message() async {
    final me = _auth.currentUser;
    final them = profile;
    if (me == null) return Result.error(Exception('Not signed in'));
    if (them == null) {
      return Result.error(Exception("This person can't get messages yet"));
    }
    return _messages.openConversation(me, them);
  }

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
    message.dispose();
    deletePost.dispose();
    _followSlot.dispose();
    super.dispose();
  }
}
