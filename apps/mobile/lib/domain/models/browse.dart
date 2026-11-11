import 'group_tournament.dart';
import 'player_profile.dart';
import 'team.dart';
import 'team_event.dart';
import 'team_post.dart';
import 'user_post.dart';

// What signed-out visitors to the website see (BrowseRepository): public
// posts, profiles, team pages and events, without who liked what.

/// A page of public posts, newest first. [next] is the cursor for the
/// page after, null on the last.
class PostPage {
  const PostPage({required this.posts, this.next});

  final List<UserPost> posts;
  final DateTime? next;

  static const empty = PostPage(posts: []);
}

/// A player as visitors see them: a private profile has only its name and
/// photo, and no posts.
class PublicProfilePage {
  const PublicProfilePage({required this.profile, required this.posts});

  final PlayerProfile profile;
  final PostPage posts;
}

/// A team or group's public page. A private group shows only its listing.
class PublicTeamPage {
  const PublicTeamPage({
    required this.listing,
    this.posts = const [],
    this.events = const [],
  });

  final TeamListing listing;
  final List<TeamPost> posts;

  /// Upcoming, soonest first.
  final List<TeamEvent> events;
}

/// A team's public event, with whose it is.
class PublicEvent {
  const PublicEvent({
    required this.event,
    required this.teamId,
    required this.teamName,
  });

  final TeamEvent event;
  final String teamId;
  final String teamName;
}

/// What's coming up across Stall 10.
class UpcomingEvents {
  const UpcomingEvents({this.events = const [], this.tournaments = const []});

  final List<PublicEvent> events;
  final List<TournamentListing> tournaments;
}
