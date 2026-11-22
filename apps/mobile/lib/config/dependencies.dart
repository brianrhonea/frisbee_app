import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../data/repositories/calendar/calendar_repository.dart';
import '../data/repositories/calendar/calendar_repository_api.dart';
import '../data/repositories/discord/discord_import_repository.dart';
import '../data/repositories/discord/discord_import_repository_firebase.dart';
import '../data/repositories/voice/voice_repository.dart';
import '../data/repositories/voice/voice_repository_livekit.dart';
import '../data/services/device_calendar_service.dart';
import '../data/services/device_permissions.dart';
import '../data/services/callable_client.dart';
import '../data/repositories/auth/auth_repository.dart';
import '../data/repositories/auth/auth_repository_firebase.dart';
import '../data/repositories/personal/personal_repository.dart';
import '../data/repositories/payment/payment_repository.dart';
import '../data/repositories/payment/payment_repository_api.dart';
import '../data/repositories/personal/personal_repository_api.dart';
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
import '../data/repositories/schedule/schedule_settings_repository.dart';
import '../data/repositories/team/team_hints_repository.dart';
import '../data/repositories/discover/discover_repository.dart';
import '../data/repositories/learn/learn_progress_repository.dart';
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
import '../data/repositories/outbox/outbox_repository.dart';
import '../data/services/api_client.dart';
import '../data/services/connectivity_service.dart';
import '../data/services/outbox_store.dart';
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
import '../data/repositories/moderation/moderation_repository.dart';
import '../data/repositories/moderation/moderation_repository_api.dart';

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
  // Reports and blocks; the block list is live for the signed-in user.
  ChangeNotifierProvider<ModerationRepository>(
    create: (context) => ModerationRepositoryApi(
      api: context.read<ApiClient?>(),
      auth: context.read<AuthRepository>(),
    ),
  ),
  // Whether Stall 10 can be reached, and what waits to go out until it can.
  ChangeNotifierProvider<ConnectivityService>(
    create: (context) => ConnectivityService.device(context.read<ApiClient?>()),
  ),
  ChangeNotifierProvider<OutboxRepository>(
    lazy: false,
    create: (context) => OutboxRepository(
      store: FileOutboxStore(),
      connectivity: context.read<ConnectivityService>(),
      auth: context.read<AuthRepository>(),
    ),
  ),
  Provider<CalendarRepository>(
    create: (context) => CalendarRepositoryApi(api: context.read<ApiClient?>()),
  ),
  Provider<PaymentRepository>(
    create: (context) => PaymentRepositoryApi(api: context.read<ApiClient?>()),
  ),
  ChangeNotifierProvider<PersonalDetailsRepository>(
    create: (context) => PersonalDetailsRepositoryApi(
      api: context.read<ApiClient?>(),
      auth: context.read<AuthRepository>(),
    ),
  ),
  Provider(create: (_) => AttachmentStorage()),
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
    // Made at start (as are the other four the offline queue sends
    // through), so queued items go out without opening their screens.
    lazy: false,
    create: (context) => TeamPostRepositoryFirebase(
      attachments: context.read<AttachmentStorage>(),
      outbox: context.read<OutboxRepository>(),
      api: context.read<ApiClient?>(),
    ),
  ),
  Provider<UserPostRepository>(
    lazy: false,
    create: (context) => UserPostRepositoryFirebase(
      attachments: context.read<AttachmentStorage>(),
      api: context.read<ApiClient?>(),
      outbox: context.read<OutboxRepository>(),
    ),
  ),
  Provider<PostCommentRepository>(
    lazy: false,
    create: (context) =>
        PostCommentRepositoryFirebase(outbox: context.read<OutboxRepository>()),
  ),
  // Drafts belong to whoever is signed in, and go when they sign out.
  // Made at start (not lazily on the first chat), so it sees every sign-out.
  Provider<MessageDraftRepository>(
    lazy: false,
    create: (context) => MessageDraftRepositoryPrefs(
      SharedPreferencesService(),
      auth: context.read<AuthRepository>(),
    ),
    dispose: (_, drafts) {
      if (drafts is MessageDraftRepositoryPrefs) drafts.dispose();
    },
  ),
  ChangeNotifierProvider<PeopleRepository>(
    create: (_) => PeopleRepositoryFirebase(),
  ),
  Provider(create: (_) => const DevicePermissions()),
  Provider(create: (_) => const DeviceCalendarService()),
  Provider<FollowRepository>(create: (_) => FollowRepositoryFirebase()),
  Provider<VideoRepository>(
    create: (context) =>
        VideoRepositoryFirebase(api: context.read<ApiClient?>()),
  ),
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
      api: context.read<ApiClient?>(),
    ),
  ),
  Provider<RankingRepository>(create: (_) => RankingRepositoryFirebase()),
  Provider<ChatRepository>(
    lazy: false,
    create: (context) => ChatRepositoryFirebase(
      attachments: context.read<AttachmentStorage>(),
      outbox: context.read<OutboxRepository>(),
      api: context.read<ApiClient?>(),
    ),
  ),
  Provider<DirectMessageRepository>(
    lazy: false,
    create: (context) => DirectMessageRepositoryFirebase(
      attachments: context.read<AttachmentStorage>(),
      search: context.read<ApiSearch>(),
      outbox: context.read<OutboxRepository>(),
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
  Provider<TeamHintsRepository>(create: (_) => TeamHintsRepositoryPrefs()),
  Provider<LearnProgressRepository>(
    create: (_) => LearnProgressRepositoryPrefs(),
  ),
  Provider<DiscoverRepository>(
    create: (context) => DiscoverRepositoryApi(api: context.read<ApiClient?>()),
  ),
  Provider<ScheduleSettingsRepository>(
    create: (_) => ScheduleSettingsRepositoryPrefs(),
  ),
  Provider<MeetingSettingsRepository>(
    create: (_) => MeetingSettingsRepositoryPrefs(SharedPreferencesService()),
  ),
  ChangeNotifierProvider<VoiceRepository>(
    create: (context) => VoiceRepositoryLiveKit(
      functions: context.read(),
      media: context.read(),
      settings: context.read(),
      teams: context.read(),
      chats: context.read(),
      auth: context.read(),
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
