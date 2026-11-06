import 'dart:typed_data';

import '../../../domain/models/browse.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/model_utils.dart';
import '../../../domain/models/player_profile.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/models/user_post.dart';
import '../../../domain/models/username.dart';
import '../../../utils/result.dart';
import '../../services/attachment_storage.dart';
import '../../services/callable_client.dart';
import 'browse_repository.dart';

/// [BrowseRepository] over the `browse` Cloud Functions, which work
/// without an account. Post photos come straight from Storage, whose rules
/// let visitors read a public post's photos.
class BrowseRepositoryFunctions implements BrowseRepository {
  BrowseRepositoryFunctions({
    required CallableClient functions,
    required AttachmentStorage attachments,
  }) : _functions = functions,
       _files = attachments;

  final CallableClient _functions;
  final AttachmentStorage _files;

  static const _searchLimit = 30;

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, Object?> data = const {},
  ]) async {
    final result = fromCallableJson(
      await _functions.call('browse-$name', data, signedOut: true),
    );
    if (result is! Map<String, dynamic>) {
      throw const CallableException("The server's answer made no sense.");
    }
    return result;
  }

  static List<Map<String, dynamic>> _list(Object? raw) => [
    for (final e in (raw as List?) ?? const [])
      if (e is Map) Map<String, dynamic>.from(e),
  ];

  static Map<String, dynamic> _data(Map<String, dynamic> hit) =>
      Map<String, dynamic>.from((hit['data'] as Map?) ?? const {});

  /// A post as the functions send it: counts instead of who liked and
  /// reposted it. The app's post widgets count the lists, so they're
  /// filled with blanks.
  static UserPost _post(Map<String, dynamic> hit) {
    final data = _data(hit);
    int n(String key) => (data[key] as num?)?.toInt() ?? 0;
    return UserPost.fromMap(hit['id'] as String? ?? '', {
      ...data,
      'likedBy': List.filled(n('likeCount'), ''),
      'repostedBy': List.filled(n('repostCount'), ''),
    });
  }

  static PostPage _page(Map<String, dynamic> result) => PostPage(
    posts: [for (final p in _list(result['posts'])) _post(p)],
    next: switch (result['next']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
  );

  @override
  Future<Result<PostPage>> feed({DateTime? before}) => guard(
    () async =>
        _page(await _call('feed', {'before': ?before?.millisecondsSinceEpoch})),
  );

  @override
  Future<Result<UserPost>> post(String id) => guard(() async {
    final result = await _call('post', {'id': id});
    return _post(Map<String, dynamic>.from(result['post'] as Map));
  });

  @override
  Future<Result<PublicProfilePage>> profile(String uid, {DateTime? before}) =>
      guard(() async {
        final result = await _call('profile', {
          'uid': uid,
          'before': ?before?.millisecondsSinceEpoch,
        });
        final profile = Map<String, dynamic>.from(
          (result['profile'] as Map?) ?? const {},
        );
        return PublicProfilePage(
          profile: PlayerProfile.fromMap(uid, profile),
          posts: _page(result),
        );
      });

  @override
  Future<Result<PublicTeamPage>> team(String id) => guard(() async {
    final result = await _call('team', {'id': id});
    return PublicTeamPage(
      listing: TeamListing.fromMap(
        id,
        Map<String, dynamic>.from((result['listing'] as Map?) ?? const {}),
      ),
      posts: [
        for (final p in _list(result['posts']))
          TeamPost.fromMap(p['id'] as String? ?? '', _data(p)),
      ],
      events: [
        for (final e in _list(result['events']))
          TeamEvent.fromMap(e['id'] as String? ?? '', _data(e)),
      ],
    );
  });

  @override
  Future<Result<UpcomingEvents>> upcoming() => guard(() async {
    final result = await _call('events');
    return UpcomingEvents(
      events: [
        for (final e in _list(result['events']))
          PublicEvent(
            event: TeamEvent.fromMap(e['id'] as String? ?? '', _data(e)),
            teamId: e['teamId'] as String? ?? '',
            teamName: e['teamName'] as String? ?? '',
          ),
      ],
      tournaments: [
        for (final t in _list(result['tournaments']))
          TournamentListing.fromMap(_data(t)),
      ],
    );
  });

  /// The longest word of [query], as the functions take it (see
  /// `searchKey` in functions/src/api/model.ts); null if there's none.
  static String? _key(String query) {
    final words = searchWords(query);
    if (words.isEmpty) return null;
    final key = (words.toList()..sort((a, b) => b.length - a.length)).first;
    return key.length > 20 ? key.substring(0, 20) : key;
  }

  Future<List<Map<String, dynamic>>> _search(String kind, String key) async =>
      _list((await _call('search', {'kind': kind, 'key': key}))['results']);

  @override
  Future<Result<List<PlayerProfile>>> searchPlayers(String query) => guard(
    () async {
      final key = _key(Username.normalize(query));
      if (key == null) return const [];
      return [
          for (final h in await _search('players', key))
            PlayerProfile.fromMap(h['id'] as String? ?? '', _data(h)),
        ].where((p) => p.matches(query)).take(_searchLimit).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    },
  );

  @override
  Future<Result<List<TeamListing>>> searchTeams(String query) => guard(
    () async {
      final key = _key(query);
      if (key == null) return const [];
      return [
          for (final h in await _search('teams', key))
            TeamListing.fromMap(h['id'] as String? ?? '', _data(h)),
        ].where((t) => t.matches(query)).take(_searchLimit).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    },
  );

  @override
  Future<Result<Uint8List>> downloadImage(ChatAttachment image) =>
      guard(() => _files.download(image));
}
