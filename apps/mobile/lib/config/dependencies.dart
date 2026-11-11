import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../data/repositories/discord/discord_import_repository.dart';
import '../data/repositories/discord/discord_import_repository_firebase.dart';
import '../data/repositories/voice/voice_repository.dart';
import '../data/repositories/voice/voice_repository_livekit.dart';
import '../data/services/device_permissions.dart';
import '../data/services/callable_client.dart';
import '../data/repositories/browse/browse_repository.dart';
import '../data/repositories/browse/browse_repository_functions.dart';
import '../data/repositories/auth/auth_repository.dart';
import '../data/repositories/auth/auth_repository_firebase.dart';
import '../data/repositories/chat/chat_repository.dart';
import '../data/repositories/chat/chat_repository_firebase.dart';
import '../data/repositories/direct_message/direct_message_repository.dart';
import '../data/repositories/direct_message/direct_message_repository_firebase.dart';
import '../data/repositories/event/event_repository.dart';
import '../data/repositories/event/event_repository_firebase.dart';
import '../data/repositories/follow/follow_repository.dart';
import '../data/repositories/follow/follow_repository_firebase.dart';
import '../data/repositories/group_tournament/group_tournament_repository.dart';
import '../data/repositories/group_tournament/group_tournament_repository_firebase.dart';
import '../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../data/repositories/hosted_tournament/hosted_tournament_repository_firebase.dart';
import '../data/repositories/ranking/ranking_repository.dart';
import '../data/repositories/ranking/ranking_repository_firebase.dart';
import '../data/repositories/meeting/meeting_repository.dart';
import '../data/repositories/meeting/meeting_repository_firebase.dart';
import '../data/repositories/meeting/meeting_settings_repository.dart';
import '../data/repositories/notification/notification_repository.dart';
import '../data/repositories/notification/notification_repository_firebase.dart';
import '../data/repositories/draft/message_draft_repository.dart';
import '../data/repositories/people/people_repository.dart';
import '../data/repositories/people/people_repository_firebase.dart';
import '../data/repositories/post_comment/post_comment_repository.dart';
import '../data/repositories/post_comment/post_comment_repository_firebase.dart';
import '../data/repositories/profile/profile_repository.dart';
import '../data/repositories/profile/profile_repository_firebase.dart';
import '../data/repositories/playbook/play_repository.dart';
import '../data/repositories/playbook/play_repository_firebase.dart';
import '../data/repositories/stats/stats_repository.dart';
import '../data/repositories/stats/stats_repository_firebase.dart';
import '../data/repositories/team/team_repository.dart';
import '../data/repositories/team/team_repository_firebase.dart';
import '../data/repositories/team_post/team_post_repository.dart';
import '../data/repositories/team_post/team_post_repository_firebase.dart';
import '../data/repositories/video/video_repository.dart';
import '../data/repositories/video/video_repository_firebase.dart';
import '../data/services/account_service.dart';
import '../data/repositories/user_post/user_post_repository.dart';
import '../data/repositories/user_post/user_post_repository_firebase.dart';
import '../data/services/attachment_storage.dart';
import '../data/services/auth_service.dart';
import '../data/services/api_client.dart';
import '../data/services/api_search.dart';
import '../data/services/feature_flags.dart';
import '../data/services/file_picker_service.dart';
import '../data/services/geocoding_service.dart';
import '../data/services/location_service.dart';
import '../data/repositories/workout_recorder/workout_recorder.dart';
import '../data/services/meeting_call.dart';
import '../data/services/meeting_call_livekit.dart';
import '../data/services/meeting_presence.dart';
import '../data/services/meeting_token_service.dart';
import '../data/services/push_service.dart';
import '../data/services/shared_preferences_service.dart';
import '../data/services/youtube_info_service.dart';
import '../firebase_options.dart';

/// Services and repositories backed by Firebase.
List<SingleChildWidget> get firebaseProviders => [
  ChangeNotifierProvider(create: (_) => FeatureFlags()..start()),
  // The Stall 10 API (apps/api); null when the build has no API_BASE_URL.
  Provider<ApiClient?>(create: (_) => ApiClient.fromEnvironment()),
  Provider(
    create: (_) => CallableClient(
      projectId: DefaultFirebaseOptions.currentPlatform.projectId,
    ),
  ),
  Provider(
    create: (context) => ApiSearch(
      functions: context.read<CallableClient>(),
      flags: context.read<FeatureFlags>(),
    ),
  ),
  Provider(create: (_) => AuthService()),
  Provider(
    create: (_) => AccountService(
      projectId: DefaultFirebaseOptions.currentPlatform.projectId,
    ),
  ),
  ChangeNotifierProvider<AuthRepository>(
    create: (context) => AuthRepositoryFirebase(
      authService: context.read<AuthService>(),
      accountService: context.read<AccountService>(),
      api: context.read<ApiClient?>(),
      flags: context.read<FeatureFlags>(),
    ),
  ),
  Provider(create: (_) => AttachmentStorage()),
  // Public pages for the website's signed-out visitors (functions/src/browse).
  Provider<BrowseRepository>(
    create: (context) => BrowseRepositoryFunctions(
      functions: context.read<CallableClient>(),
      attachments: context.read<AttachmentStorage>(),
    ),
  ),
  Provider<TeamRepository>(
    create: (context) => TeamRepositoryFirebase(
      attachments: context.read<AttachmentStorage>(),
      search: context.read<ApiSearch>(),
      api: context.read<ApiClient?>(),
      flags: context.read<FeatureFlags>(),
    ),
  ),
  Provider<PlayRepository>(create: (_) => PlayRepositoryFirebase()),
  Provider<ProfileRepository>(
    create: (context) => ProfileRepositoryFirebase(
      search: context.read<ApiSearch>(),
      attachments: context.read<AttachmentStorage>(),
      api: context.read<ApiClient?>(),
      flags: context.read<FeatureFlags>(),
    ),
  ),
  Provider<EventRepository>(create: (_) => EventRepositoryFirebase()),
  Provider<TeamPostRepository>(
    create: (context) => TeamPostRepositoryFirebase(
      attachments: context.read<AttachmentStorage>(),
    ),
  ),
  Provider<UserPostRepository>(
    create: (context) => UserPostRepositoryFirebase(
      attachments: context.read<AttachmentStorage>(),
    ),
  ),
  Provider<PostCommentRepository>(
    create: (_) => PostCommentRepositoryFirebase(),
  ),
  Provider<MessageDraftRepository>(
    create: (_) => MessageDraftRepositoryPrefs(SharedPreferencesService()),
  ),
  ChangeNotifierProvider<PeopleRepository>(
    create: (_) => PeopleRepositoryFirebase(),
  ),
  Provider(create: (_) => const DevicePermissions()),
  Provider<FollowRepository>(create: (_) => FollowRepositoryFirebase()),
  Provider<VideoRepository>(create: (_) => VideoRepositoryFirebase()),
  Provider<YouTubeInfoService>(create: (_) => YouTubeInfoService()),
  Provider<GeocodingService>(create: (_) => GeocodingService()),
  Provider<LocationService>(create: (_) => GeolocatorLocationService()),
  // App-wide so a recording keeps going while the user browses.
  ChangeNotifierProvider(
    create: (context) =>
        WorkoutRecorder(location: context.read<LocationService>()),
  ),
  Provider<GroupTournamentRepository>(
    create: (_) => GroupTournamentRepositoryFirebase(),
  ),
  Provider<HostedTournamentRepository>(
    create: (context) => HostedTournamentRepositoryFirebase(
      functions: context.read<CallableClient>(),
    ),
  ),
  Provider<RankingRepository>(create: (_) => RankingRepositoryFirebase()),
  Provider<ChatRepository>(
    create: (context) =>
        ChatRepositoryFirebase(attachments: context.read<AttachmentStorage>()),
  ),
  Provider<DirectMessageRepository>(
    create: (context) => DirectMessageRepositoryFirebase(
      attachments: context.read<AttachmentStorage>(),
      search: context.read<ApiSearch>(),
    ),
  ),
  Provider(
    create: (context) => FilePickerService(flags: context.read<FeatureFlags>()),
  ),
  Provider(
    create: (_) => MeetingTokenService(
      projectId: DefaultFirebaseOptions.currentPlatform.projectId,
    ),
  ),
  Provider<MeetingRepository>(
    create: (context) =>
        MeetingRepositoryFirebase(tokens: context.read<MeetingTokenService>()),
  ),
  Provider<DiscordImportRepository>(
    create: (context) => DiscordImportRepositoryFirebase(
      functions: context.read<CallableClient>(),
    ),
  ),
  Provider<MeetingMediaService>(create: (_) => LiveKitMediaService()),
  Provider(create: (_) => MeetingPresence()),
  Provider<MeetingSettingsRepository>(
    create: (_) => MeetingSettingsRepositoryPrefs(SharedPreferencesService()),
  ),
  ChangeNotifierProvider<VoiceRepository>(
    create: (context) => VoiceRepositoryLiveKit(
      functions: context.read(),
      media: context.read(),
      settings: context.read(),
    ),
  ),
  Provider(create: (_) => PushService()),
  Provider<NotificationRepository>(
    create: (context) =>
        NotificationRepositoryFirebase(push: context.read<PushService>()),
  ),
  Provider<StatsRepository>(
    create: (context) =>
        StatsRepositoryFirebase(teamRepository: context.read<TeamRepository>()),
  ),
];
