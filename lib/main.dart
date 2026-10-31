import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'config/dependencies.dart';
import 'data/repositories/auth/auth_repository.dart';
import 'data/repositories/notification/notification_repository.dart';
import 'data/repositories/theme/theme_repository.dart';
import 'data/repositories/theme/theme_repository_prefs.dart';
import 'data/services/shared_preferences_service.dart';
import 'firebase_options.dart';
import 'routing/router.dart';
import 'ui/core/themes/theme.dart';
import 'ui/core/ui/brand.dart';
import 'ui/meetings/view_models/meeting_alerts_viewmodel.dart';
import 'ui/meetings/widgets/meeting_alerts.dart';
import 'routing/open_link.dart';

/// Run with `--dart-define=USE_EMULATORS=true` to use local Firebase emulators.
const _useEmulators = bool.fromEnvironment('USE_EMULATORS');

/// Run with `--dart-define=FIRESTORE_MEMORY_CACHE=true` to keep Firestore's
/// cache in memory. On desktop only one process can open the on-disk cache
/// (a second copy of the app crashes), so use this for the second copy when
/// testing two accounts on one computer.
const _memoryCache = bool.fromEnvironment('FIRESTORE_MEMORY_CACHE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plays uploaded team videos.
  MediaKit.ensureInitialized();
  Logger.root.level = kDebugMode ? Level.ALL : Level.WARNING;
  Logger.root.onRecord.listen(
    (r) => debugPrint('${r.level.name} ${r.loggerName}: ${r.message}'),
  );

  DefaultFirebaseOptions.ensureConfigured();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (_memoryCache) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  }
  if (_useEmulators) {
    final host = defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  }

  final themeRepository = await ThemeRepositoryPrefs.load(
    SharedPreferencesService(),
  );

  runApp(
    MultiProvider(
      providers: [
        ...firebaseProviders,
        ChangeNotifierProvider<ThemeRepository>.value(value: themeRepository),
      ],
      child: const FrisbeeApp(),
    ),
  );
}

class FrisbeeApp extends StatefulWidget {
  const FrisbeeApp({super.key});

  @override
  State<FrisbeeApp> createState() => _FrisbeeAppState();
}

class _FrisbeeAppState extends State<FrisbeeApp> {
  late final AuthRepository _auth = context.read();
  late final NotificationRepository _notifications = context.read();
  late final GoRouter _router = router(_auth);
  late final MeetingAlertsViewModel _meetingAlerts;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _opened;
  String? _syncedUid;

  /// A tapped notification waiting for sign-in to finish.
  String? _pendingRoute;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuth);
    _meetingAlerts = MeetingAlertsViewModel(
      authRepository: _auth,
      notificationRepository: _notifications,
      presence: context.read(),
    );
    _opened = _notifications.openedRoutes.listen((route) {
      _pendingRoute = route;
      _openPending();
    });
    _onAuth();
  }

  /// Registers this device for push whenever someone signs in.
  void _onAuth() {
    final uid = _auth.currentUser?.uid;
    if (uid != null && uid != _syncedUid) {
      unawaited(_notifications.syncDevice(uid));
    }
    _syncedUid = uid;
    _openPending();
  }

  void _openPending() {
    final route = _pendingRoute;
    if (route == null || !_auth.isReady || !_auth.isAuthenticated) return;
    _pendingRoute = null;
    // After the redirect away from the splash page has settled.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _router.openLink(route),
    );
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    _opened?.cancel();
    _meetingAlerts.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: appName,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: context.watch<ThemeRepository>().themeMode,
    routerConfig: _router,
    scaffoldMessengerKey: _messengerKey,
    builder: (_, child) => MeetingAlerts(
      viewModel: _meetingAlerts,
      router: _router,
      messengerKey: _messengerKey,
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
