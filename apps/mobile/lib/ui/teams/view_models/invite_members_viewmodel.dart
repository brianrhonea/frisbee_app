import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/invite_code.dart';
import '../../../domain/models/team.dart';
import '../../core/ui/brand.dart' show appName;
import '../../../utils/command.dart';
import '../../../utils/invite_links.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';

/// An invite link to share anywhere, people search (each person invited
/// gets an in-app invite plus the link as a direct message), and a group's
/// join requests. A team's link expires after [expiry]; [start] (the dialog
/// opening) mints it, so it's ready to copy or share, as on the website.
/// A group's link just opens its page. Owners and
/// organizers only (the rules check), or, without [withLink], a community's
/// admins inviting to one of its teams: they can't make the team's links,
/// so the message just says where to accept.
class InviteMembersViewModel extends ChangeNotifier {
  InviteMembersViewModel({
    required this.team,
    required TeamRepository teamRepository,
    required DirectMessageRepository directMessageRepository,
    required AuthRepository authRepository,
    this.withLink = true,
    this.debounce = AppMotion.sheet,
  }) : _teams = teamRepository,
       _people = directMessageRepository,
       _auth = authRepository {
    invite = Command1<void, UserProfile>(_invite);
    createLink = Command0<Uri>(_createLink);
    approveJoinRequest = Command1<void, GroupJoinRequest>(
      (r) => _teams.approveJoinRequest(team.id, r),
    );
    declineJoinRequest = Command1<void, String>(
      (uid) => _teams.declineJoinRequest(team.id, uid),
    );
    if (hasJoinRequests) {
      _requestSub = _teams.watchJoinRequests(team.id).listen((r) {
        _joinRequests = r;
        notifyListeners();
      }, onError: (Object _) {});
    }
    // Groups have no code; the link opens their page.
    if (team.isCommunity) _link = InviteLinks.group(team.id);
  }

  Uri? _link;
  DateTime? _linkExpiresAt;

  /// The link that joins the team (or opens the group); null until
  /// [createLink] makes one for the team.
  Uri? get link => _link;

  /// When the team's link stops working; null for groups.
  DateTime? get linkExpiresAt => _linkExpiresAt;

  /// Whether links expire (teams) or not (groups).
  bool get linkExpires => !team.isCommunity;

  InviteLinkExpiry _expiry = InviteLinkExpiry.standard;

  /// How long the next team link works.
  InviteLinkExpiry get expiry => _expiry;

  /// Picks how long the link works; a link already made keeps its own
  /// expiry. Once [start]ed a new one is made at once, else on the next
  /// copy or share.
  void setExpiry(InviteLinkExpiry value) {
    if (value == _expiry || !linkExpires) return;
    _expiry = value;
    _link = null;
    _linkExpiresAt = null;
    notifyListeners();
    if (_started) createLink.execute();
  }

  bool _started = false;

  /// The dialog opened: make the team's link now, so Invite then Copy (or
  /// Share) is all it takes.
  void start() {
    if (_started) return;
    _started = true;
    if (withLink && linkExpires) createLink.execute();
  }

  StreamSubscription<List<GroupJoinRequest>>? _requestSub;
  List<GroupJoinRequest> _joinRequests = const [];

  /// Whether join requests are shown: a group that approves members, to
  /// its member managers (the rules let only them read requests).
  bool get hasJoinRequests =>
      withLink &&
      team.isCommunity &&
      team.requiresApproval &&
      (_auth.currentUser != null &&
          team.has(_auth.currentUser!.uid, TeamPermission.manageMembers));

  /// People asking to join, oldest first.
  List<GroupJoinRequest> get joinRequests => _joinRequests;

  late final Command1<void, GroupJoinRequest> approveJoinRequest;
  late final Command1<void, String> declineJoinRequest;

  /// Makes the team's link if there isn't one yet; returns the link.
  late final Command0<Uri> createLink;

  /// What sharing [link] says, e.g. "Join Cascades on Stall 10: …".
  String shareTextFor(Uri link) => 'Join ${team.name} on $appName: $link';

  /// [shareTextFor] the current link; null until there is one.
  String? get shareText => switch (_link) {
    final l? => shareTextFor(l),
    null => null,
  };

  Future<Result<Uri>> _createLink() async {
    if (_link case final l?) return Result.ok(l);
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    final result = await _teams.createInviteLink(team.id, user.uid, _expiry);
    switch (result) {
      case Ok(:final value):
        _link = InviteLinks.join(value.code);
        _linkExpiresAt = value.expiresAt;
        // The dialog may have closed while the link was made.
        if (!_disposed) notifyListeners();
        return Result.ok(_link!);
      case Error(:final error):
        return Result.error(error);
    }
  }

  final Team team;

  /// Offers the invite link, and sends it with each invite.
  final bool withLink;

  final TeamRepository _teams;
  final DirectMessageRepository _people;
  final AuthRepository _auth;

  static const minQueryLength = 2;

  /// How long typing pauses before searching.
  final Duration debounce;

  late final Command1<void, UserProfile> invite;

  Timer? _timer;
  String _query = '';
  int _searchId = 0;

  List<UserProfile> _results = const [];
  List<UserProfile> get results => _results;

  bool _searching = false;
  bool get searching => _searching;

  Object? _error;
  Object? get error => _error;

  final Set<String> _invited = {};
  final List<UserProfile> _invitedPeople = [];

  /// Who was invited while this dialog was open, newest first. A team's
  /// pending invites live under each invitee, so there's no list to read
  /// back; this is the session's.
  List<UserProfile> get invitedPeople => List.unmodifiable(_invitedPeople);

  String get query => _query;

  bool isMember(String uid) => team.members.containsKey(uid);

  /// Invited while this dialog was open.
  bool wasInvited(String uid) => _invited.contains(uid);

  /// Searches for [query] once typing pauses.
  void search(String query) {
    _query = query.trim();
    _timer?.cancel();
    if (_query.length < minQueryLength) {
      _searchId++;
      _results = const [];
      _searching = false;
      _error = null;
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();
    _timer = Timer(debounce, _run);
  }

  Future<void> _run() async {
    final id = ++_searchId;
    final result = await _people.searchPeople(
      _query,
      excludeUid: _auth.currentUser?.uid ?? '',
    );
    // A newer search started while this one ran.
    if (id != _searchId || _disposed) return;
    _searching = false;
    switch (result) {
      case Ok(:final value):
        _results = value;
        _error = null;
      case Error(:final error):
        _results = const [];
        _error = error;
    }
    notifyListeners();
  }

  Future<Result<void>> _invite(UserProfile person) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    if (isMember(person.uid)) {
      return Result.error(Exception('${person.name} is already a member.'));
    }
    final result = await _teams.inviteToTeam(team, person.uid, user);
    if (result is! Ok || _disposed) return result;
    _invited.add(person.uid);
    _invitedPeople
      ..removeWhere((p) => p.uid == person.uid)
      ..insert(0, person);
    notifyListeners();
    final String text;
    if (withLink) {
      // The link too, so they can join from a message or another device.
      final link = await _createLink();
      if (link case Error(:final error)) return Result.error(error);
      text = shareTextFor((link as Ok<Uri>).value);
    } else {
      text =
          'I invited you to join ${team.name} on $appName. Accept it from '
          'your Teams tab.';
    }
    final convo = await _people.openConversation(user, person);
    return switch (convo) {
      Ok(:final value) => _people.sendMessage(value, author: user, text: text),
      Error(:final error) => Result.error(error),
    };
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _requestSub?.cancel();
    invite.dispose();
    createLink.dispose();
    approveJoinRequest.dispose();
    declineJoinRequest.dispose();
    super.dispose();
  }
}
