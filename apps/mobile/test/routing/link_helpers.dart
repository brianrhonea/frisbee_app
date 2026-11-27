// Shared by the link tests (N1, N6, N11): the page each kind of link must
// open, and a way to open a link the way the app does from outside.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/calendar/widgets/calendars_screen.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_room_screen.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/explore/widgets/rankings_screen.dart';
import 'package:frisbee_app/ui/learn/widgets/learn_screen.dart';
import 'package:frisbee_app/ui/meetings/widgets/meeting_detail_screen.dart';
import 'package:frisbee_app/ui/meetings/widgets/meeting_room_screen.dart';
import 'package:frisbee_app/ui/messages/widgets/direct_chat_screen.dart';
import 'package:frisbee_app/ui/messages/widgets/inbox_screen.dart';
import 'package:frisbee_app/ui/notifications/widgets/follow_requests_screen.dart';
import 'package:frisbee_app/ui/playbook/widgets/play_editor_screen.dart';
import 'package:frisbee_app/ui/playbook/widgets/whiteboard_screen.dart';
import 'package:frisbee_app/ui/posts/widgets/post_detail_screen.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_detail_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/my_event_detail_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_screen.dart';
import 'package:frisbee_app/ui/settings/widgets/settings_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/join_link_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_bracket_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/live_draft_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/respond_screen.dart';
import 'package:frisbee_app/ui/videos/widgets/video_screen.dart';

/// The page each logical name in `shared_links.json` opens.
const linkPages = <String, Type>{
  'team': TeamHomeScreen,
  'invite': JoinLinkScreen,
  'post': PostDetailScreen,
  'player': PlayerProfileScreen,
  'explore': ExploreScreen,
  'rankings': RankingsScreen,
  'tournament': HostedTournamentScreen,
  'respond': RespondScreen,
  'bracket': HostedBracketScreen,
  'liveDraft': LiveDraftScreen,
  'meeting': MeetingDetailScreen,
  'learn': LearnScreen,
};

/// Other pages the notification links open.
const notificationPages = <String, Type>{
  'inbox': InboxScreen,
  'teams': TeamsScreen,
  'schedule': ScheduleScreen,
  'chatRoom': ChatRoomScreen,
  'directChat': DirectChatScreen,
  'whiteboard': WhiteboardScreen,
  'play': PlayEditorScreen,
  'video': VideoScreen,
  'calendars': CalendarsScreen,
  'meetingRoom': MeetingRoomScreen,
  'followRequests': FollowRequestsScreen,
  'teamEvent': EventDetailScreen,
  'myEvent': MyEventDetailScreen,
  'settings': SettingsScreen,
  ...linkPages,
};

/// Fails if the page on screen is go_router's "not found".
void expectFound(WidgetTester t, String link) {
  expect(
    find.text('Page Not Found'),
    findsNothing,
    reason: '$link opened the not-found page',
  );
}
