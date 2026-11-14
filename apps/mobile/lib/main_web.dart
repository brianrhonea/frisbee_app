import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'config/dependencies.dart';
import 'data/repositories/auth/auth_repository.dart';
import 'data/repositories/personal/personal_repository.dart';
import 'data/repositories/theme/theme_repository.dart';
import 'data/repositories/theme/theme_repository_prefs.dart';
import 'data/services/shared_preferences_service.dart';
import 'firebase_options.dart';
import 'routing/web_router.dart';
import 'ui/core/themes/theme.dart';
import 'ui/core/ui/brand.dart';

/// The website's entry point, served at /app (see scripts/build_site.sh).
/// The same repositories and screens as the app (lib/main.dart), framed by
/// a web top bar and limited to search, profiles, team pages and events.
/// It skips what only the app does: push, meeting alerts, video
/// playback setup and the phone orientation lock.
///
/// Run with `flutter run -d chrome -t lib/main_web.dart
/// --dart-define-from-file=secrets.local.json`.
const _useEmulators = bool.fromEnvironment('USE_EMULATORS');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // /explore, not /#/explore.
  usePathUrlStrategy();
  Logger.root.level = kDebugMode ? Level.ALL : Level.WARNING;
  Logger.root.onRecord.listen(
    (r) => debugPrint('${r.level.name} ${r.loggerName}: ${r.message}'),
  );

  DefaultFirebaseOptions.ensureConfigured();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (_useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
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
      child: const StallWebApp(),
    ),
  );
}

class StallWebApp extends StatefulWidget {
  const StallWebApp({super.key});

  @override
  State<StallWebApp> createState() => _StallWebAppState();
}

class _StallWebAppState extends State<StallWebApp> {
  late final GoRouter _router = webRouter(
    context.read<AuthRepository>(),
    personal: context.read<PersonalDetailsRepository>(),
  );

  @override
  void dispose() {
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
  );
}
