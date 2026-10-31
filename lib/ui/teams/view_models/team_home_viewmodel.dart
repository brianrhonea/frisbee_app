import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/team_post/team_post_repository.dart';
import '../../../data/services/file_picker_service.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/team_post.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Backs the team home page. Members get the team summary, upcoming
/// events and every post; anyone else who finds the team gets its public
/// page: directory listing, public events and public posts.
class TeamHomeViewModel extends ChangeNotifier {
  TeamHomeViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required EventRepository eventRepository,
    required TeamPostRepository teamPostRepository,
    required AuthRepository authRepository,
    required FilePickerService filePicker,
    DateTime Function()? clock,
  }) : _teams = teamRepository,
       _events = eventRepository,
       _posts = teamPostRepository,
       _auth = authRepository,
       _picker = filePicker,
       _clock = clock ?? DateTime.now {
    updateTeam = Command1<void, Team>(_teams.updateTeam);
    leaveTeam = Command0<void>(() => _teams.removeMember(teamId, uid));
    deleteTeam = Command0<void>(_deleteTeam);
    savePost = Command1<void, PostDraft>(_savePost);
    deletePost = Command1<void, String>((id) => _posts.deletePost(teamId, id));
    joinTeam = Command1<String, String>(_joinTeam);

    _listingSub = _teams
        .watchListing(teamId)
        .listen(
          (l) {
            _listing = l;
            _listingLoaded = true;
            _onChange();
          },
          onError: (Object _) {
            _listingLoaded = true;
            _onChange();
          },
        );
    _watchTeam();
  }

  /// Upcoming events shown on the home page; the rest are in Team Events.
  static const upcomingLimit = 3;

  final String teamId;
  final TeamRepository _teams;
  final EventRepository _events;
  final TeamPostRepository _posts;
  final AuthRepository _auth;
  final FilePickerService _picker;
  final DateTime Function() _clock;
  final _downloads = <String, Future<Result<Uint8List>>>{};

  late final StreamSubscription<TeamListing?> _listingSub;
  StreamSubscription<Team?>? _teamSub;
  StreamSubscription<List<TeamEvent>>? _eventsSub;
  StreamSubscription<List<TeamPost>>? _postsSub;

  /// Whether the event and post streams are the members' (true) or the
  /// public ones (false); null before either is watched.
  bool? _watchingAsMember;
  bool _published = false;

  Team? _team;
  bool _teamLoaded = false;
  TeamListing? _listing;
  bool _listingLoaded = false;

  /// Only members may read the team itself, so an error just means the
  /// user isn't on it (or it's gone); the public listing takes over.
  void _watchTeam() {
    _teamSub?.cancel();
    _teamSub = _teams
        .watchTeam(teamId)
        .listen(
          (t) {
            _team = (t?.members.containsKey(uid) ?? false) ? t : null;
            _teamLoaded = true;
            _onChange();
          },
          onError: (Object _) {
            _team = null;
            _teamLoaded = true;
            _onChange();
          },
        );
  }

  void _onChange() {
    _watchContent();
    _publishListing();
    notifyListeners();
  }

  /// (Re)subscribes to events and posts once membership is known, and
  /// when it changes, e.g. after joining.
  void _watchContent() {
    if (!loaded || summary == null) return;
    final member = isMember;
    if (_watchingAsMember == member) return;
    _watchingAsMember = member;
    _eventsSub?.cancel();
    _postsSub?.cancel();
    _contentError = null;
    _eventList = const [];
    _postList = const [];
    _eventsSub =
        (member
                ? _events.watchEvents(teamId)
                : _events.watchPublicEvents(teamId))
            .listen((e) {
              _eventList = e;
              notifyListeners();
            }, onError: _onContentError);
    _postsSub = _posts.watchPosts(teamId, publicOnly: !member).listen((p) {
      _postList = p;
      notifyListeners();
    }, onError: _onContentError);
  }

  /// Teams from before the directory, or edited elsewhere, get their
  /// listing (re)written when an admin opens them.
  void _publishListing() {
    final team = _team;
    if (_published || team == null || !canEdit || !_listingLoaded) return;
    if (_listing?.sameAs(team) ?? false) return;
    _published = true;
    _teams.publishListing(team);
  }

  void _onContentError(Object e) {
    _contentError = e;
    notifyListeners();
  }

  /// True once membership and the listing are known.
  bool get loaded => _teamLoaded && _listingLoaded;

  String get uid => _auth.currentUser?.uid ?? '';

  /// The team, for members; null for everyone else.
  Team? get team => _team;

  bool get isMember => _team != null;

  /// Name, division, level and city: from the team for members, else the
  /// public listing. Null if the team doesn't exist (or isn't listed).
  TeamListing? get summary => switch (_team) {
    final t? => TeamListing.of(t),
    null => _listing,
  };

  TeamRole? get myRole => _team?.roleOf(uid);
  bool get canEdit => myRole?.canEdit ?? false;
  bool get isOwner => myRole == TeamRole.owner;

  /// Owners, coaches and captains write posts.
  bool get canPost => canEdit;

  int get memberCount => _team?.members.length ?? 0;

  List<TeamEvent> _eventList = const [];
  List<TeamPost> _postList = const [];
  Object? _contentError;

  /// Events or posts failed to load; the rest of the page still works.
  Object? get contentError => _contentError;

  /// Events that haven't finished yet, soonest first. Public events only
  /// for non-members.
  List<TeamEvent> get upcomingEvents {
    final now = _clock();
    return [
      for (final e in _eventList)
        if (!(e.endsAt ?? e.startsAt.add(const Duration(hours: 2))).isBefore(
          now,
        ))
          e,
    ];
  }

  /// Newest first. Public posts only for non-members.
  List<TeamPost> get posts => _postList;

  late final Command1<void, Team> updateTeam;
  late final Command0<void> leaveTeam;
  late final Command0<void> deleteTeam;

  /// Creates or edits a post, uploading its new photos.
  late final Command1<void, PostDraft> savePost;
  late final Command1<void, String> deletePost;

  /// Joins with an invite code; the result is the joined team's id, which
  /// may be another team if the code is for one.
  late final Command1<String, String> joinTeam;

  Future<Result<void>> _deleteTeam() async {
    final t = _team;
    if (t == null) return Result.error(Exception('Team not loaded'));
    return _teams.deleteTeam(t);
  }

  Future<Result<void>> _savePost(PostDraft draft) async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    return _posts.savePost(teamId, draft, me);
  }

  /// Lets an admin pick photos for a post; empty when cancelled. Photos
  /// over [maxAttachmentBytes] are left out and reported as an error.
  Future<Result<List<NewAttachment>>> pickImages() async {
    final List<PickedFile> picked;
    try {
      picked = await _picker.pick(imagesOnly: true);
    } on Exception catch (e) {
      return Result.error(e);
    }
    final images = <NewAttachment>[];
    final tooLarge = <String>[];
    for (final f in picked) {
      if ((f.size ?? 0) > maxAttachmentBytes) {
        tooLarge.add(f.name);
        continue;
      }
      final a = NewAttachment(name: f.name, bytes: await f.read());
      if (a.tooLarge || !a.isImage) {
        tooLarge.add(f.name);
      } else {
        images.add(a);
      }
    }
    if (tooLarge.isNotEmpty && images.isEmpty) {
      return Result.error(AttachmentTooLargeException(tooLarge.join(', ')));
    }
    return Result.ok(images);
  }

  /// A post photo's bytes, fetched once per photo.
  Future<Result<Uint8List>> imageData(ChatAttachment image) =>
      _downloads[image.path] ??= _posts.downloadImage(image).then((r) {
        if (r is Error) _downloads.remove(image.path);
        return r;
      });

  Future<Result<String>> _joinTeam(String code) async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    final result = await _teams.joinTeam(code, me);
    if (result case Ok(value: final id) when id == teamId) _watchTeam();
    return result;
  }

  @override
  void dispose() {
    _listingSub.cancel();
    _teamSub?.cancel();
    _eventsSub?.cancel();
    _postsSub?.cancel();
    super.dispose();
  }
}
