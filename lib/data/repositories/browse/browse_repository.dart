import 'dart:typed_data';

import '../../../domain/models/browse.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/player_profile.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/result.dart';

/// Everything public on Stall 10, readable without an account: the website
/// shows it to signed-out visitors (functions/src/browse). Private profiles
/// and private groups are left out by the server.
abstract class BrowseRepository {
  /// The newest public posts; [before] pages back.
  Future<Result<PostPage>> feed({DateTime? before});

  /// One public post.
  Future<Result<UserPost>> post(String id);

  /// A player's public profile and newest posts.
  Future<Result<PublicProfilePage>> profile(String uid, {DateTime? before});

  /// A team or group's public page.
  Future<Result<PublicTeamPage>> team(String id);

  /// Public team events and group tournaments still to come.
  Future<Result<UpcomingEvents>> upcoming();

  /// Players whose name matches [query].
  Future<Result<List<PlayerProfile>>> searchPlayers(String query);

  /// Teams and groups whose name or city matches [query].
  Future<Result<List<TeamListing>>> searchTeams(String query);

  /// A photo on a public post.
  Future<Result<Uint8List>> downloadImage(ChatAttachment image);
}
