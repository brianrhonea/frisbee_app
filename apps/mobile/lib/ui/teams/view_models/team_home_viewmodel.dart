import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../data/repositories/hosted_tournament/tournament_days.dart';
import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/chat/chat_repository.dart';
import '../../../data/repositories/chat/team_chat_activity.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/team/team_hints_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/team_post/team_post_repository.dart';
import '../../../data/services/file_picker_service.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/team_page.dart';
import '../../../domain/models/team_post.dart';
import 'team_post_comments_viewmodel.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/group_tournament/group_tournament_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/tournament_engine/tournament_day.dart';
import '../../follow/view_models/follow_viewmodel.dart';

/// Whether [typed] confirms deleting a team called [name]: the same name,
/// ignoring case and spaces at the ends, as the API checks.
bool deleteNameMatches(String name, String typed) =>
    typed.trim().toLowerCase() == name.trim().toLowerCase();

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
    FollowRepository? followRepository,
    NotificationRepository? notificationRepository,
    GroupTournamentRepository? groupTournamentRepository,
    HostedTournamentRepository? tournamentRepository,
    TeamHintsRepository? hints,
    ChatRepository? chatRepository,
    DirectMessageRepository? directMessageRepository,
    DateTime Function()? clock,
  }) : _teams = teamRepository,
       _chats = chatRepository,
       _dms = directMessageRepository,
       _hints = hints ?? TeamHintsRepositoryMemory(),
       _events = eventRepository,
       _posts = teamPostRepository,
       _auth = authRepository,
       _picker = filePicker,
       _groupTournaments = groupTournamentRepository,
       _hosted = tournamentRepository,
       _clock = clock ?? DateTime.now {
    _followSlot = FollowSlot(
      followRepository: followRepository,
      notificationRepository: notificationRepository,
      authRepository: authRepository,
    );
    updateTeam = Command1<void, Team>(_teams.updateTeam);
    leaveTeam = Command0<void>(() => _teams.removeMember(teamId, uid));
    deleteTeam = Command1<void, String>(_deleteTeam);
    savePost = Command1<void, PostDraft>(_savePost);
    deletePost = Command1<void, String>((id) => _posts.deletePost(teamId, id));
    pinPost = Command1<void, ({String postId, String? unpin})>(
      (a) => _posts.pinPost(teamId, a.postId, unpin: a.unpin),
    );
    unpinPost = Command1<void, String>((id) => _posts.unpinPost(teamId, id));
    joinTeam = Command1<String, String>(_joinTeam);
    joinGroup = Command0<void>(_joinGroup);
    declineInvite = Command1<void, String>(_declineInvite);
    cancelJoinRequest = Command0<void>(
      () => _teams.cancelJoinRequest(teamId, uid),
    );
    setNextRsvp = Command1<void, ({String eventId, RsvpStatus? status})>(
      (a) => _events.setRsvp(teamId, a.eventId, uid, a.status),
    );
    messageOrganizer = Command1<String, CommunityOrganizer>(_message);

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
    _hints.sectionsHintDismissed(teamId).then((d) {
      if (_disposed) return;
      _hintDismissed = d;
      notifyListeners();
    });
    final me = authRepository.currentUser?.uid ?? '';
    if (tournamentRepository != null && me.isNotEmpty) {
      _days = TournamentDays(
        repository: tournamentRepository,
        teams: _teams
            .watchTeam(teamId)
            .map(
              (t) =>
                  t != null && t.members.containsKey(me) ? [t] : const <Team>[],
            ),
        uid: me,
        clock: clock,
      )..addListener(notifyListeners);
    }
  }

  /// Upcoming events shown on the home page; the rest are in Team Events.
  static const upcomingLimit = 3;

  /// Newest posts loaded on the team page.
  static const postLimit = 30;

  final String teamId;
  final TeamRepository _teams;
  final EventRepository _events;
  final TeamPostRepository _posts;
  final AuthRepository _auth;
  final FilePickerService _picker;
  final GroupTournamentRepository? _groupTournaments;
  final HostedTournamentRepository? _hosted;
  StreamSubscription<List<TournamentListing>>? _listingsSub;
  List<TournamentListing> _tournamentListings = const [];

  /// A group's tournaments as anyone sees them, newest first, so people
  /// can open and follow one they aren't playing in.
  List<TournamentListing> get tournamentListings => _tournamentListings;
  final DateTime Function() _clock;
  final TeamHintsRepository _hints;
  bool _disposed = false;

  /// Null until read from the device.
  bool? _hintDismissed;

  /// How long a team counts as brand new, for the sections hint.
  static const newTeamFor = Duration(days: 30);

  /// The one-time hint for the owner of a brand-new team that still has
  /// every optional section off: they're in Settings › Sections.
  bool get showSectionsHint {
    final t = _team;
    if (t == null || _hintDismissed != false || !isOwner) return false;
    if (t.kind != TeamKind.team || t.isLeagueTeam) return false;
    if (OptionalSection.values.any(t.hasSection)) return false;
    final made = t.createdAt;
    return made == null || _clock().difference(made) < newTeamFor;
  }

  void dismissSectionsHint() {
    _hintDismissed = true;
    notifyListeners();
    _hints.dismissSectionsHint(teamId);
  }

  final _downloads = <String, Future<Result<Uint8List>>>{};

  late final StreamSubscription<TeamListing?> _listingSub;
  StreamSubscription<Team?>? _teamSub;
  StreamSubscription<List<TeamEvent>>? _eventsSub;
  StreamSubscription<List<TeamPost>>? _postsSub;
  StreamSubscription<List<TeamPost>>? _pinnedSub;

  /// Whose event and post streams are watched: the public ones, or a
  /// member's (with what a community lets them see); null before either.
  String? _watchingAsMember;
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
    _watchChat();
    _watchListings();
    _watchEntered();
    _loadInvites();
    _watchContent();
    _watchRequest();
    _watchJoinRequests();
    _publishListing();
    notifyListeners();
  }

  List<TeamTournamentInvite> _invites = const [];
  bool _invitesAsked = false;

  /// Tournament and league invites waiting on the team, for its admins
  /// (manageTeam): the page's Accept / Decline card. Empty for others.
  List<TeamTournamentInvite> get tournamentInvites => _invites;

  /// Run the team's entries: answer invites, enter tournaments.
  bool get canManageTeam => _team?.has(uid, TeamPermission.manageTeam) ?? false;

  /// Turns down a tournament's invite (its id); the card drops it.
  late final Command1<void, String> declineInvite;

  /// Asks once the team (and the user's say on it) is known.
  void _loadInvites({bool again = false}) {
    final repo = _hosted;
    if (repo == null || _team?.kind != TeamKind.team || !canManageTeam) return;
    if (_invitesAsked && !again) return;
    _invitesAsked = true;
    repo.teamInvites(teamId).then((r) {
      if (_disposed) return;
      if (r case Ok(:final value)) {
        _invites = value;
        notifyListeners();
      }
    });
  }

  /// Fetches the invites again (back from accepting one, say).
  void refreshInvites() => _loadInvites(again: true);

  Future<Result<void>> _declineInvite(String tournamentId) async {
    final repo = _hosted;
    if (repo == null) return Result.error(Exception('Not available.'));
    final r = await repo.declineInvite(tournamentId, teamId);
    if (r is Ok) {
      _invites = [
        for (final i in _invites)
          if (i.tournamentId != tournamentId) i,
      ];
      notifyListeners();
    }
    return r;
  }

  final ChatRepository? _chats;
  StreamSubscription<List<ChatRoom>>? _roomsSub;
  StreamSubscription<Map<String, Map<String, DateTime>>>? _readsSub;
  String? _roomsKey;
  List<ChatRoom> _rooms = const [];
  Map<String, DateTime> _reads = const {};

  /// Watches the team's rooms and the member's read times for the chat
  /// tile. Both are the shell's shared listeners ([SharedStreams]), so
  /// this adds no reads. Re-asks when the member's roles change.
  void _watchChat() {
    final chats = _chats;
    final team = _team;
    if (chats == null) return;
    if (team == null) {
      _roomsSub?.cancel();
      _roomsSub = null;
      _roomsKey = null;
      _rooms = const [];
      return;
    }
    _readsSub ??= chats.watchReads(uid).listen((r) {
      _reads = r[teamId] ?? const {};
      notifyListeners();
    }, onError: (Object _) {});
    final key = [
      team.roleOf(uid)?.name,
      ...?team.memberRoles[uid],
      team.has(uid, TeamPermission.manageChats),
    ].join(',');
    if (key == _roomsKey) return;
    _roomsKey = key;
    _roomsSub?.cancel();
    _roomsSub = chats.watchRooms(team, uid).listen((r) {
      _rooms = r;
      notifyListeners();
    }, onError: (Object _) {});
  }

  /// The chat tile: how many of the team's rooms the member can read have
  /// messages they haven't read (rooms, not messages; teamChatSummary).
  int get newInChat {
    final team = _team;
    if (team == null) return 0;
    return TeamChatSummary.fromReadable(team, [
      for (final r in _rooms)
        if (r.accessFor(team, uid).canRead) r,
    ], _reads).unreadRooms.length;
  }

  /// The next event (the first of [upcomingEvents]) for the "going" tile.
  TeamEvent? get nextEvent => upcomingEvents.firstOrNull;

  /// How many said Going to [nextEvent] (`goingCount` in packages/shared).
  int get nextGoing => [
    for (final a in nextEvent?.rsvps.values ?? const <RsvpStatus>[])
      if (a == RsvpStatus.going) a,
  ].length;

  // The community page (redesign F27): the next pickup card, the chat
  // section and the organizers section.

  /// The viewer's answer to [nextEvent]; null when unanswered.
  RsvpStatus? get myNextRsvp => nextEvent?.rsvpOf(uid);

  /// Amber "RSVP needed" on the pickup card: a member who hasn't answered
  /// [nextEvent] (which isn't over: [upcomingEvents] leaves those out).
  bool get nextNeedsRsvp => isMember && nextEvent != null && myNextRsvp == null;

  /// RSVPs to the next event through the schedule's path
  /// ([EventRepository.setRsvp]); a null status takes the answer back.
  late final Command1<void, ({String eventId, RsvpStatus? status})> setNextRsvp;

  /// Picks [status] on [nextEvent]; picking the current answer (or null)
  /// takes it back, as on the event screen.
  void answerNext(RsvpStatus? status) {
    final e = nextEvent;
    if (e == null || !isMember || setNextRsvp.running) return;
    setNextRsvp.execute((
      eventId: e.id,
      status: status == myNextRsvp ? null : status,
    ));
  }

  /// "New event" on the empty pickup card.
  bool get canAddEvents =>
      _team?.has(uid, TeamPermission.manageEvents) ?? false;

  /// The chat section: the rooms the member can read, unread ones first
  /// and marked, up to [chatSectionMax]; `more` are on the chat page.
  ({List<({ChatRoom room, bool unread})> rooms, int more}) get chatSection {
    final team = _team;
    if (team == null) return (rooms: const [], more: 0);
    final s = TeamChatSummary.fromReadable(team, [
      for (final r in _rooms)
        if (r.accessFor(team, uid).canRead) r,
    ], _reads);
    return chatSectionRooms(s.rooms, s.unreadRooms);
  }

  /// The organizers section: the owner and those who run the community.
  List<CommunityOrganizer> get organizers => switch (_team) {
    final t? => communityOrganizers(t),
    null => const [],
  };

  final DirectMessageRepository? _dms;

  /// Whether the organizers' Message buttons can open a conversation.
  bool get canMessage => _dms != null;

  /// Opens (or starts) a direct conversation with an organizer, as a
  /// profile's Message button does; the result is the conversation id.
  late final Command1<String, CommunityOrganizer> messageOrganizer;

  Future<Result<String>> _message(CommunityOrganizer o) async {
    final dms = _dms;
    final me = _auth.currentUser;
    if (dms == null || me == null) {
      return Result.error(Exception('Not signed in'));
    }
    return dms.openConversation(me, UserProfile(uid: o.uid, name: o.name));
  }

  StreamSubscription<List<GroupJoinRequest>>? _joinRequestsSub;
  int _joinRequestCount = 0;

  /// How many people are asking to join, for the Invite button's badge:
  /// a group that approves members, to members who manage members.
  int get joinRequestCount => _joinRequestCount;

  void _watchJoinRequests() {
    final team = _team;
    final want =
        team != null &&
        team.isCommunity &&
        team.requiresApproval &&
        canManageMembers;
    if (want == (_joinRequestsSub != null)) return;
    _joinRequestsSub?.cancel();
    _joinRequestsSub = null;
    _joinRequestCount = 0;
    if (!want) return;
    _joinRequestsSub = _teams.watchJoinRequests(teamId).listen((r) {
      _joinRequestCount = r.length;
      notifyListeners();
    }, onError: (Object _) {});
  }

  void _watchListings() {
    final repo = _groupTournaments;
    if (repo == null || _listingsSub != null || !isGroup) return;
    _listingsSub = repo.watchListings(teamId).listen((l) {
      _tournamentListings = l;
      notifyListeners();
    }, onError: (Object _) {});
  }

  StreamSubscription<List<EnteredTournament>>? _enteredSub;
  List<EnteredTournament> _entered = const [];

  /// Whether Tournaments is a tab of its own on this team's page: a team
  /// (not a community) with a tournament ahead; members only, as only
  /// they can read its entries.
  bool get tournamentsTab => hasTournamentAhead(_entered, _clock());

  /// Watches the tournaments a team has entered while the user is on it.
  void _watchEntered() {
    final repo = _hosted;
    final want = repo != null && _team?.kind == TeamKind.team;
    if (want == (_enteredSub != null)) return;
    _enteredSub?.cancel();
    _enteredSub = null;
    _entered = const [];
    if (!want) return;
    _enteredSub = repo.watchEnteredBy(teamId).listen((e) {
      _entered = e;
      notifyListeners();
    }, onError: (Object _) {});
  }

  StreamSubscription<bool>? _requestSub;
  bool _requestPending = false;

  /// Watches the user's own join request while they're outside a group
  /// that needs approval, or a team that takes requests (F26).
  void _watchRequest() {
    final want = loaded && !isMember && (summary?.takesRequests ?? false);
    if (want == (_requestSub != null)) return;
    _requestSub?.cancel();
    _requestSub = null;
    _requestPending = false;
    if (!want) return;
    _requestSub = _teams.watchMyJoinRequest(teamId, uid).listen((pending) {
      _requestPending = pending;
      notifyListeners();
    }, onError: (Object _) {});
  }

  /// (Re)subscribes to events and posts once membership is known, and
  /// when it changes, e.g. after joining.
  void _watchContent() {
    if (!loaded || summary == null) return;
    final member = isMember;
    final audience = _team?.eventAudienceOf(uid);
    final key = !member
        ? 'public'
        : audience == null
        ? 'member'
        : 'member:${(audience.toList()..sort()).join(',')}';
    if (_watchingAsMember == key) return;
    _watchingAsMember = key;
    _eventsSub?.cancel();
    _postsSub?.cancel();
    _pinnedSub?.cancel();
    _contentError = null;
    _eventList = const [];
    _postList = const [];
    _pinnedList = const [];
    // A private group shows outsiders nothing beyond its listing.
    if (isPrivateToMe) {
      _eventsSub = null;
      _postsSub = null;
      _pinnedSub = null;
      return;
    }
    // Only what's coming up is shown here; Team Events has the history.
    final since = _clock().subtract(const Duration(days: 1));
    _eventsSub =
        (member
                ? _events.watchEvents(teamId, since: since, audience: audience)
                : _events.watchPublicEvents(teamId, since: since))
            .listen((e) {
              _eventList = e;
              notifyListeners();
            }, onError: _onContentError);
    _postsSub = _posts
        .watchPosts(teamId, publicOnly: !member, limit: postLimit)
        .listen((p) {
          _postList = p;
          notifyListeners();
        }, onError: _onContentError);
    // Pinned posts can be older than the newest [postLimit] (redesign F24).
    _pinnedSub = _posts.watchPinnedPosts(teamId, publicOnly: !member).listen(
      (p) {
        _pinnedList = p;
        notifyListeners();
      },
      // Pins are extra: without them (say, before the public + pinnedAt
      // index is built) the feed still shows, newest first.
      onError: (Object _) {},
    );
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

  late final FollowSlot _followSlot;

  /// The team's Follow button, for people not on it; null for members
  /// (their feed already has every post) and until membership is known.
  FollowViewModel? get follow {
    final s = summary;
    if (!loaded || isMember || s == null) return null;
    return _followSlot.of(FollowTarget.team(teamId, s.name));
  }

  /// True once membership and the listing are known.
  bool get loaded => _teamLoaded && _listingLoaded;

  String get uid => _auth.currentUser?.uid ?? '';

  /// The team, for members; null for everyone else.
  Team? get team => _team;

  bool get isMember => _team != null;

  /// A community group rather than a team.
  bool get isGroup => summary?.isCommunity ?? false;

  /// A private group the user isn't in, or a team whose public page is
  /// off: only its listing is visible.
  bool get isPrivateToMe => !isMember && (summary?.hidesPage ?? false);

  /// A youth team the user isn't on: its roster is for its members only
  /// (the API refuses anyone else), so the page says so in its place.
  bool get youthRosterPrivate {
    final s = summary;
    return !isMember &&
        s != null &&
        !s.isCommunity &&
        s.level == CompetitionLevel.youth;
  }

  /// The user asked to join this group and is waiting for approval.
  bool get requestPending => _requestPending;

  /// Name, division, level and city: from the team for members, else the
  /// public listing. Null if the team doesn't exist (or isn't listed).
  TeamListing? get summary => switch (_team) {
    final t? => TeamListing.of(t),
    null => _listing,
  };

  TeamRole? get myRole => _team?.roleOf(uid);
  bool get canEdit => _team?.canEdit(uid) ?? false;
  bool get isOwner => myRole == TeamRole.owner;

  /// Invite, approve and remove members.
  bool get canManageMembers =>
      _team?.has(uid, TeamPermission.manageMembers) ?? false;

  /// Members who can manage the team write posts.
  bool get canPost => canEdit;

  int get memberCount => _team?.members.length ?? 0;

  List<TeamEvent> _eventList = const [];
  List<TeamPost> _postList = const [];
  List<TeamPost> _pinnedList = const [];
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

  /// The feed: [pinnedPosts] first, then the rest newest first. Public
  /// posts only for non-members.
  List<TeamPost> get posts => [...pinnedPosts, ...otherPosts];

  ({List<TeamPost> pinned, List<TeamPost> rest}) get _feed =>
      arrangeTeamFeed(_pinnedList, _postList);

  /// Posts the team's admins pinned, newest pin first (redesign F24).
  List<TeamPost> get pinnedPosts => _feed.pinned;

  /// The rest of the feed, newest first.
  List<TeamPost> get otherPosts => _feed.rest;

  /// Admins pin posts and delete anyone's comment (through the API).
  bool get canPin => canPost && _posts.canUseFeedExtras;

  /// Members read and write comments (through the API to write).
  bool get canComment => isMember && _posts.canUseFeedExtras;

  /// Pins a post; with [TeamPost.pinsMax] pinned, [unpin] names the one
  /// to take down (the view asks which).
  late final Command1<void, ({String postId, String? unpin})> pinPost;
  late final Command1<void, String> unpinPost;

  /// The comment thread of [post], for its sheet (the sheet disposes it).
  TeamPostCommentsViewModel commentsFor(TeamPost post) =>
      TeamPostCommentsViewModel(
        teamId: teamId,
        postId: post.id,
        repository: _posts,
        uid: uid,
        canModerate: canPost,
      );

  late final Command1<void, Team> updateTeam;
  late final Command0<void> leaveTeam;

  /// Deletes the team; the argument is the name the owner typed.
  late final Command1<void, String> deleteTeam;

  /// Creates or edits a post, uploading its new photos.
  late final Command1<void, PostDraft> savePost;
  late final Command1<void, String> deletePost;

  /// Joins with an invite code; the result is the joined team's id, which
  /// may be another team if the code is for one.
  late final Command1<String, String> joinTeam;

  /// Joins an open group, or asks to join one that needs approval or a
  /// team that takes join requests (F26).
  late final Command0<void> joinGroup;

  /// Withdraws a pending join request.
  late final Command0<void> cancelJoinRequest;

  Future<Result<void>> _joinGroup() async {
    final me = _auth.currentUser;
    final listing = summary;
    if (me == null) return Result.error(Exception('Not signed in'));
    if (listing == null) return Result.error(Exception('Community not found'));
    if (listing.takesRequests) return _teams.requestToJoin(teamId, me);
    if (!listing.isCommunity) {
      return Result.error(Exception('Join a team with an invite code.'));
    }
    final result = await _teams.joinGroup(teamId, me);
    if (result is Ok) _watchTeam();
    return result;
  }

  Future<Result<void>> _deleteTeam(String typedName) async {
    final t = _team;
    if (t == null) return Result.error(Exception('Team not loaded'));
    // The screen asks first; the API (or rules) refuse it too.
    if (t.members.length > 1) {
      return Result.error(
        Exception('Remove the other members or transfer ownership first.'),
      );
    }
    if (!deleteNameMatches(t.name, typedName)) {
      return Result.error(Exception('Type the name exactly to delete it.'));
    }
    _deleteProgress = (done: 0, total: 1, step: 'Getting ready');
    notifyListeners();
    final result = await _teams.deleteTeam(
      t,
      name: typedName,
      onProgress: (p) {
        _deleteProgress = p;
        notifyListeners();
      },
    );
    _deleteProgress = null;
    notifyListeners();
    return result;
  }

  DeleteProgress? _deleteProgress;

  /// While the team is being deleted, how far it's got.
  DeleteProgress? get deleteProgress => _deleteProgress;

  Future<Result<void>> _savePost(PostDraft draft) async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    return _posts.savePost(teamId, draft, me);
  }

  /// Lets an admin pick photos for a post; empty when cancelled. Photos
  /// over [maxAttachmentBytes] are left out and reported as an error.
  Future<Result<List<NewAttachment>>> pickImages({bool camera = false}) =>
      pickPostImages(_picker, camera: camera);

  /// Whether posts can take a photo with the camera here.
  bool get canUseCamera => _picker.canUseCamera;

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
    _disposed = true;
    _listingSub.cancel();
    _listingsSub?.cancel();
    _requestSub?.cancel();
    _joinRequestsSub?.cancel();
    _enteredSub?.cancel();
    _teamSub?.cancel();
    _eventsSub?.cancel();
    _postsSub?.cancel();
    _pinnedSub?.cancel();
    _roomsSub?.cancel();
    _readsSub?.cancel();
    _followSlot.dispose();
    _days
      ?..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }

  TournamentDays? _days;

  /// The team's tournament day (today, or this evening for tomorrow),
  /// shown in place of its next event; members only.
  TeamTournamentDay? get tournamentDay => _days?.forTeam(teamId);
}

/// Picks photos for a post, or takes one with the [camera]; empty when
/// cancelled. Photos are shrunk first; ones still over
/// [maxAttachmentBytes] are left out and reported as an error.
Future<Result<List<NewAttachment>>> pickPostImages(
  FilePickerService picker, {
  bool camera = false,
}) async {
  final List<PickedFile> picked;
  try {
    picked = camera
        ? [?await picker.takePhoto()]
        : await picker.pick(imagesOnly: true);
  } on Exception catch (e) {
    return Result.error(e);
  }
  final images = <NewAttachment>[];
  final tooLarge = <String>[];
  for (final f in picked) {
    final a = await readAttachment(picker, f);
    if (a == null || a.tooLarge || !a.isImage) {
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
