import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/profile/profile_repository.dart';
import '../../../data/repositories/stats/stats_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/player_profile.dart';
import '../../../domain/models/roster_player.dart';
import '../../../domain/models/stats.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../follow/view_models/follow_viewmodel.dart';

/// A team whose roster the user isn't linked to yet, and the roster spots
/// they could claim, best name match first.
typedef ClaimableTeam = ({Team team, List<RosterPlayer> players});

/// A player's profile. Anyone sees what the player published; on their own
/// profile the player sees their stats computed live from the games of
/// every team whose roster they're linked to, and their app publishes the
/// parts they choose to show.
///
/// With [FollowRepository] and [UserPostRepository] it also shows follower
/// counts, the Follow button and the player's posts.
class PlayerProfileViewModel extends ChangeNotifier {
  PlayerProfileViewModel({
    required this.uid,
    required ProfileRepository profileRepository,
    required AuthRepository authRepository,
    required TeamRepository teamRepository,
    required StatsRepository statsRepository,
    required DirectMessageRepository directMessageRepository,
    FollowRepository? followRepository,
    UserPostRepository? userPostRepository,
    NotificationRepository? notificationRepository,
  }) : _profiles = profileRepository,
       _auth = authRepository,
       _teamRepo = teamRepository,
       _stats = statsRepository,
       _dms = directMessageRepository,
       _userPosts = userPostRepository,
       _followSlot = FollowSlot(
         followRepository: followRepository,
         notificationRepository: notificationRepository,
         authRepository: authRepository,
       ) {
    saveDetails = Command1<void, ProfileDetails>(_saveDetails);
    claim = Command1<void, (String, String)>(
      (r) => _teamRepo.linkPlayer(r.$1, r.$2, _me),
    );
    unclaim = Command1<void, (String, String)>(
      (r) => _teamRepo.linkPlayer(r.$1, r.$2, null),
    );
    message = Command0<String>(_message);
    deletePost = Command1<void, String>(
      (id) async =>
          await _userPosts?.deletePost(id) ??
          Result.error(Exception('Posts are unavailable')),
    );
    if (_userPosts case final posts?) {
      _subs.add(
        posts
            .watchPostsBy(uid)
            .listen(
              (p) {
                _posts = p;
                _postsLoaded = true;
                notifyListeners();
              },
              onError: (Object e) {
                _postsError = e;
                _postsLoaded = true;
                notifyListeners();
              },
            ),
      );
    }
    if (followRepository != null) {
      _subs.add(
        followRepository.watchCounts(FollowTarget.userKey(uid)).listen((c) {
          _counts = c;
          notifyListeners();
        }, onError: (Object _) {}),
      );
    }
    _subs.add(
      _profiles
          .watchProfile(uid)
          .listen(
            (p) {
              _profile = p;
              _profileLoaded = true;
              _maybePublish();
              notifyListeners();
            },
            onError: (Object e) {
              _error = e;
              _profileLoaded = true;
              notifyListeners();
            },
          ),
    );
    if (isMe) {
      _subs.add(
        _teamRepo.watchMyTeams(uid).listen(_onTeams, onError: (Object _) {}),
      );
    }
  }

  /// Whose profile this is.
  final String uid;
  final ProfileRepository _profiles;
  final AuthRepository _auth;
  final TeamRepository _teamRepo;
  final StatsRepository _stats;
  final DirectMessageRepository _dms;
  final UserPostRepository? _userPosts;
  final FollowSlot _followSlot;
  final _downloads = <String, Future<Result<Uint8List>>>{};
  final List<StreamSubscription<Object?>> _subs = [];

  String get _me => _auth.currentUser?.uid ?? '';

  /// The signed-in user's own profile.
  bool get isMe => uid == _me;

  PlayerProfile? _profile;
  bool _profileLoaded = false;
  Object? _error;

  bool get loaded => _profileLoaded && (!isMe || _teamsLoaded);
  Object? get error => _error;

  /// The published profile; null if the player has none.
  PlayerProfile? get profile => _profile;

  /// The name to show: the account's for the user, else the profile's.
  String get name =>
      isMe ? (_auth.currentUser?.label ?? '') : (_profile?.name ?? '');

  String? get photoUrl =>
      isMe ? _auth.currentUser?.photoUrl : _profile?.photoUrl;

  ProfileDetails get details => _profile?.details ?? const ProfileDetails();

  ProfileVisibility get visibility => details.visibility;

  /// What to show: the live summary on the user's own profile (all of it,
  /// hidden parts included), else what the player published.
  ProfileSummary get summary =>
      isMe ? _live : (_profile?.summary ?? const ProfileSummary());

  /// Whether others see the stats, teams and recent games. Always true
  /// for what another player published, since hidden parts aren't.
  bool get showsStats => isMe || visibility.stats;
  bool get showsTeams => isMe || visibility.teams;
  bool get showsGames => isMe || visibility.games;

  // Seasons --------------------------------------------------------------

  /// Seasons with stats, newest first.
  List<String> get seasons =>
      summary.seasons.keys.toList()..sort((a, b) => b.compareTo(a));

  String? _season;

  /// The season "By the numbers" shows; null for every season.
  String? get season => seasons.contains(_season) ? _season : null;

  void selectSeason(String? season) {
    _season = season;
    notifyListeners();
  }

  /// Totals for [season].
  StatTotals get totals => switch (season) {
    final s? => summary.seasons[s] ?? const StatTotals(),
    null => summary.career,
  };

  /// Jersey number and position from the first team that has one.
  ProfileTeam? get primaryTeam =>
      summary.teams.where((t) => t.number != null).firstOrNull ??
      summary.teams.where((t) => t.kind == TeamKind.team).firstOrNull;

  // The user's own teams and stats ----------------------------------------

  bool _teamsLoaded = false;
  List<Team> _teams = const [];
  final Map<String, StreamSubscription<List<RosterPlayer>>> _rosterSubs = {};
  final Map<String, List<RosterPlayer>> _rosters = {};
  final Map<String, StreamSubscription<List<StatsGame>>> _gameSubs = {};
  final Map<String, List<StatsGame>> _games = {};
  ProfileSummary _live = const ProfileSummary();

  void _onTeams(List<Team> teams) {
    _teams = [...teams]..sort((a, b) => a.name.compareTo(b.name));
    _teamsLoaded = true;
    final ids = {for (final t in teams) t.id};
    for (final id in _rosterSubs.keys.toList()) {
      if (ids.contains(id)) continue;
      _rosterSubs.remove(id)?.cancel();
      _gameSubs.remove(id)?.cancel();
      _rosters.remove(id);
      _games.remove(id);
    }
    for (final t in teams.where((t) => !t.isCommunity)) {
      _rosterSubs[t.id] ??= _teamRepo
          .watchRoster(t.id)
          .listen(
            (r) {
              _rosters[t.id] = r;
              _watchGames(t.id);
              _recompute();
            },
            onError: (Object _) {
              _rosters[t.id] = const [];
              _recompute();
            },
          );
    }
    _recompute();
  }

  /// Follows a team's games once the user is linked to its roster.
  void _watchGames(String teamId) {
    if (_mine(teamId) == null || _gameSubs.containsKey(teamId)) return;
    _gameSubs[teamId] = _stats
        .watchGames(teamId)
        .listen(
          (g) {
            _games[teamId] = g;
            _recompute();
          },
          onError: (Object _) {
            _games[teamId] = const [];
            _recompute();
          },
        );
  }

  RosterPlayer? _mine(String teamId) =>
      _rosters[teamId]?.where((p) => p.userId == uid).firstOrNull;

  /// The user's roster spot on [team], if they've claimed one.
  RosterPlayer? linkedPlayer(Team team) => _mine(team.id);

  /// Teams where the user hasn't claimed a roster spot, with the spots
  /// they could claim.
  List<ClaimableTeam> get claimable => [
    for (final t in _teams)
      if (!t.isCommunity && _rosters.containsKey(t.id) && _mine(t.id) == null)
        if (_unlinked(t.id) case final players when players.isNotEmpty)
          (team: t, players: players),
  ];

  /// Unclaimed spots on [teamId]'s roster, those matching the user's name
  /// first.
  List<RosterPlayer> _unlinked(String teamId) {
    final me = name.toLowerCase().trim();
    final first = me.split(RegExp(r'\s+')).first;
    int score(RosterPlayer p) {
      final n = p.name.toLowerCase().trim();
      if (n == me) return 0;
      if (first.isNotEmpty && n.split(RegExp(r'\s+')).first == first) return 1;
      return 2;
    }

    return [
      for (final p in _rosters[teamId] ?? const <RosterPlayer>[])
        if (p.userId == null || p.userId!.isEmpty) p,
    ]..sort((a, b) {
      final s = score(a).compareTo(score(b));
      return s != 0 ? s : a.name.compareTo(b.name);
    });
  }

  /// Whether every linked team's games have loaded.
  bool get _statsLoaded =>
      _teams
          .where((t) => !t.isCommunity)
          .every((t) => _rosters.containsKey(t.id)) &&
      _gameSubs.keys.every(_games.containsKey);

  void _recompute() {
    final teams = <ProfileTeam>[];
    final seasons = <String, StatTotals>{};
    final games = <ProfileGame>[];
    for (final t in _teams) {
      final mine = t.isCommunity ? null : _mine(t.id);
      final role = t.roleOf(uid);
      teams.add(
        ProfileTeam(
          id: t.id,
          name: t.name,
          kind: t.kind,
          subtitle: TeamListing.of(t).subtitle,
          role: role == null ? null : t.roleLabel(role),
          number: mine?.number,
          position: mine?.position.label,
        ),
      );
      if (mine == null) continue;
      for (final g in _games[t.id] ?? const <StatsGame>[]) {
        if (g.points.isEmpty) continue;
        final p = StatSheet.fromPoints(g.points).players[mine.id];
        if (p == null || (p.pointsPlayed == 0 && p.touches == 0)) continue;
        final line = StatTotals.fromPlayer(p);
        final year = '${g.date.year}';
        seasons[year] = (seasons[year] ?? const StatTotals()) + line;
        games.add(
          ProfileGame(
            teamName: t.name,
            opponent: g.opponent,
            date: g.date,
            ourScore: g.ourScore,
            theirScore: g.theirScore,
            line: line,
          ),
        );
      }
    }
    games.sort((a, b) => b.date.compareTo(a.date));
    _live = ProfileSummary(
      teams: teams,
      seasons: seasons,
      games: games.take(ProfileSummary.maxGames).toList(),
    );
    _maybePublish();
    notifyListeners();
  }

  /// [_live] with the parts the user hides left out.
  ProfileSummary get _visibleLive {
    final v = visibility;
    return ProfileSummary(
      teams: v.teams ? _live.teams : const [],
      seasons: v.stats ? _live.seasons : const {},
      games: v.games ? _live.games : const [],
    );
  }

  bool _publishing = false;

  /// Publishing is a write, and stats change with every save while one of
  /// the user's games is tracked, so stats-only changes wait at least this
  /// long between publishes. Team and visibility changes go out at once.
  static const publishGap = Duration(seconds: 60);
  DateTime? _lastPublish;
  ProfileVisibility? _publishedVisibility;
  Timer? _publishLater;

  /// Keeps the published summary in step with the live one.
  Future<void> _maybePublish() async {
    final user = _auth.currentUser;
    if (!isMe || user == null || _publishing) return;
    if (_publishLater != null) return;
    if (!_profileLoaded || !_teamsLoaded || !_statsLoaded) return;
    // Users without a display name aren't in the directory.
    if ((user.displayName?.trim() ?? '').isEmpty) return;
    final visible = _visibleLive;
    final published = _profile?.summary ?? const ProfileSummary();
    if (_profile != null && visible.sameAs(published)) return;
    final last = _lastPublish;
    final statsOnly =
        _profile != null &&
        visibility == _publishedVisibility &&
        listEquals(visible.teams, published.teams);
    if (last != null && statsOnly) {
      final wait = publishGap - DateTime.now().difference(last);
      if (wait > Duration.zero) {
        _publishLater = Timer(wait, () {
          _publishLater = null;
          _maybePublish();
        });
        return;
      }
    }
    _lastPublish = DateTime.now();
    _publishedVisibility = visibility;
    _publishing = true;
    try {
      await _profiles.publishSummary(
        user,
        visible,
        tags: PlayerProfile(
          uid: uid,
          name: user.label,
          details: details,
          summary: visible,
        ).searchTags,
      );
    } finally {
      _publishing = false;
    }
  }

  // Commands -------------------------------------------------------------

  /// Saves the user's bio, details and what others may see.
  late final Command1<void, ProfileDetails> saveDetails;

  /// Claims roster spot (teamId, playerId) for the user.
  late final Command1<void, (String, String)> claim;

  /// Unlinks the user from roster spot (teamId, playerId).
  late final Command1<void, (String, String)> unclaim;

  /// Opens a direct-message conversation with this player; the result is
  /// its id.
  late final Command0<String> message;

  // Follows and posts -----------------------------------------------------

  /// Whether this profile shows posts and follows at all.
  bool get social => _userPosts != null;

  List<UserPost> _posts = const [];
  bool _postsLoaded = false;
  Object? _postsError;
  FollowCounts _counts = const FollowCounts();

  /// The player's posts, newest first.
  List<UserPost> get posts => _posts;
  bool get postsLoaded => _postsLoaded;
  Object? get postsError => _postsError;
  int get followers => _counts.followers;
  int get following => _counts.following;

  /// The Follow button; null on the user's own profile, and until the
  /// profile loads.
  FollowViewModel? get follow => isMe || !_profileLoaded
      ? null
      : _followSlot.of(FollowTarget.user(uid, name, photoUrl: photoUrl));

  /// Deletes one of the user's own posts, by id.
  late final Command1<void, String> deletePost;

  /// A post photo's bytes, fetched once per photo.
  Future<Result<Uint8List>> imageData(ChatAttachment image) =>
      _downloads[image.path] ??=
          (_userPosts?.downloadImage(image) ??
                  Future.value(
                    Result<Uint8List>.error(Exception('No posts here')),
                  ))
              .then((r) {
                if (r is Error) _downloads.remove(image.path);
                return r;
              });

  Future<Result<void>> _saveDetails(ProfileDetails d) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    if ((user.displayName?.trim() ?? '').isEmpty) {
      return Result.error(
        Exception('Set a display name first, in Settings below.'),
      );
    }
    final v = d.visibility;
    return _profiles.saveDetails(
      user,
      d,
      tags: PlayerProfile(
        uid: uid,
        name: user.label,
        details: d,
        summary: ProfileSummary(teams: v.teams ? _live.teams : const []),
      ).searchTags,
    );
  }

  Future<Result<String>> _message() async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    return _dms.openConversation(
      me,
      UserProfile(uid: uid, name: name, photoUrl: photoUrl),
    );
  }

  @override
  void dispose() {
    _publishLater?.cancel();
    for (final s in [..._subs, ..._rosterSubs.values, ..._gameSubs.values]) {
      s.cancel();
    }
    saveDetails.dispose();
    claim.dispose();
    unclaim.dispose();
    message.dispose();
    deletePost.dispose();
    _followSlot.dispose();
    super.dispose();
  }
}
