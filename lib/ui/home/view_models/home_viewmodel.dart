import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/team_post/team_post_repository.dart';
import '../../../data/repositories/tournament/tournament_repository.dart';
import '../../../data/services/file_picker_service.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/schedule_entry.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/models/tournament.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../schedule/view_models/my_schedule.dart';
import '../../teams/view_models/team_home_viewmodel.dart' show pickPostImages;

/// A post on the community feed and the team it's from.
class FeedPost {
  const FeedPost({required this.team, required this.post});

  final Team team;
  final TeamPost post;
}

/// A post to save on [teamId]'s page.
typedef FeedPostDraft = ({String teamId, PostDraft draft});

/// The community feed: posts from every team and group the user is on,
/// newest first, with what's coming up on their schedule beside it.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required AuthRepository authRepository,
    required TeamRepository teamRepository,
    required EventRepository eventRepository,
    MeetingRepository? meetingRepository,
    required TeamPostRepository teamPostRepository,
    required TournamentRepository tournamentRepository,
    required FilePickerService filePicker,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _teamRepo = teamRepository,
       _posts = teamPostRepository,
       _picker = filePicker,
       _clock = clock ?? DateTime.now {
    joinTeam = Command1<String, String>(_joinTeam);
    savePost = Command1<void, FeedPostDraft>(_savePost);
    deletePost = Command1<void, FeedPost>(
      (p) => _posts.deletePost(p.team.id, p.post.id),
    );
    _feed = MySchedule(
      teamRepository: teamRepository,
      eventRepository: eventRepository,
      meetingRepository: meetingRepository,
      uid: _auth.currentUser?.uid,
      clock: _clock,
    )..addListener(_onFeed);
    _subs.add(
      tournamentRepository.watchTournaments().listen((t) {
        _tournaments = t;
        notifyListeners();
      }, onError: (_) {}),
    );
  }

  final AuthRepository _auth;
  final TeamRepository _teamRepo;
  final TeamPostRepository _posts;
  final FilePickerService _picker;
  final DateTime Function() _clock;
  late final MySchedule _feed;
  final List<StreamSubscription<Object?>> _subs = [];
  final Map<String, StreamSubscription<List<TeamPost>>> _postSubs = {};
  final Map<String, List<TeamPost>> _postsByTeam = {};
  final _downloads = <String, Future<Result<Uint8List>>>{};

  /// Events listed under "Coming up".
  static const upcomingLimit = 4;

  /// Joins by invite code; result value is the team id.
  late final Command1<String, String> joinTeam;

  /// Creates or edits a post on one of the user's teams.
  late final Command1<void, FeedPostDraft> savePost;
  late final Command1<void, FeedPost> deletePost;

  AppUser? get user => _auth.currentUser;

  String get _uid => user?.uid ?? '';

  DateTime get now => _clock();

  /// First name for the greeting: the first word of the display name, or
  /// the part of the email before "@".
  String get firstName {
    final u = user;
    final name = u?.displayName?.trim() ?? '';
    if (name.isNotEmpty) return name.split(RegExp(r'\s+')).first;
    final email = u?.email ?? '';
    return email.contains('@') ? email.split('@').first : 'player';
  }

  // Teams ------------------------------------------------------------------

  List<Team> get teams => _feed.teams;

  /// False until the team list first loads, so the join card doesn't flash.
  bool get teamsLoaded => _feed.teamsLoaded;

  bool canEdit(Team team) => team.canEdit(_uid);

  /// Teams the user may post on: those they own, coach or captain.
  List<Team> get postableTeams => teams.where(canEdit).toList();

  /// The city most of the user's teams play in, for the page's eyebrow.
  String? get homeCity {
    final counts = <String, int>{};
    for (final t in teams) {
      if (t.city.trim().isEmpty) continue;
      counts.update(t.city.trim(), (n) => n + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) return null;
    return (counts.entries.toList()..sort((a, b) => b.value - a.value))
        .first
        .key;
  }

  void _onFeed() {
    _watchPosts();
    notifyListeners();
  }

  Future<Result<String>> _joinTeam(String code) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    return _teamRepo.joinTeam(code, user);
  }

  // Posts ------------------------------------------------------------------

  bool _postsLoaded = false;

  /// False until every team's posts have loaded once.
  bool get postsLoaded => _postsLoaded || (teamsLoaded && teams.isEmpty);

  /// Posts from all the user's teams, newest first.
  List<FeedPost> get posts {
    final byId = {for (final t in teams) t.id: t};
    final list = [
      for (final e in _postsByTeam.entries)
        if (byId[e.key] case final team?)
          for (final p in e.value) FeedPost(team: team, post: p),
    ];
    list.sort((a, b) => TeamPost.newestFirst(a.post, b.post));
    return list;
  }

  /// Follows each team's posts, and stops following teams the user left.
  void _watchPosts() {
    final ids = {for (final t in teams) t.id};
    for (final id in _postSubs.keys.toList()) {
      if (ids.contains(id)) continue;
      _postSubs.remove(id)?.cancel();
      _postsByTeam.remove(id);
    }
    for (final id in ids) {
      if (_postSubs.containsKey(id)) continue;
      _postSubs[id] = _posts
          .watchPosts(id)
          .listen(
            (p) {
              _postsByTeam[id] = p;
              _checkPostsLoaded();
              notifyListeners();
            },
            onError: (Object _) {
              _postsByTeam[id] = const [];
              _checkPostsLoaded();
              notifyListeners();
            },
          );
    }
    _checkPostsLoaded();
  }

  void _checkPostsLoaded() {
    if (_postsLoaded || !teamsLoaded) return;
    _postsLoaded = teams.every((t) => _postsByTeam.containsKey(t.id));
  }

  Future<Result<void>> _savePost(FeedPostDraft d) async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    return _posts.savePost(d.teamId, d.draft, me);
  }

  /// Lets an admin pick photos for a post; empty when cancelled.
  Future<Result<List<NewAttachment>>> pickImages() => pickPostImages(_picker);

  /// A post photo's bytes, fetched once per photo.
  Future<Result<Uint8List>> imageData(ChatAttachment image) =>
      _downloads[image.path] ??= _posts.downloadImage(image).then((r) {
        if (r is Error) _downloads.remove(image.path);
        return r;
      });

  // Schedule ---------------------------------------------------------------

  /// The next event of one of the user's teams, for the "Up next" card.
  ScheduleEntry? get nextTeamEvent =>
      _feed.upcoming(limit: 1, personal: false).firstOrNull;

  /// Upcoming team and personal events after [nextTeamEvent], team events
  /// first within a day.
  List<ScheduleEntry> get upcomingEvents {
    final featured = nextTeamEvent?.event.id;
    return _feed
        .prioritized(limit: upcomingLimit + 1)
        .where((e) => e.event.id != featured)
        .take(upcomingLimit)
        .toList();
  }

  /// [team]'s next event that hasn't ended.
  ScheduleEntry? nextEventFor(Team team) =>
      _feed.upcoming().where((e) => e.team?.id == team.id).firstOrNull;

  List<Tournament> _tournaments = const [];

  /// The next USA Ultimate tournament, for "Around the league".
  Tournament? get nextTournament {
    final now = _clock();
    return _tournaments.where((t) => t.isUpcoming(now)).firstOrNull;
  }

  @override
  void dispose() {
    _feed
      ..removeListener(_onFeed)
      ..dispose();
    for (final s in [..._subs, ..._postSubs.values]) {
      s.cancel();
    }
    joinTeam.dispose();
    savePost.dispose();
    deletePost.dispose();
    super.dispose();
  }
}
