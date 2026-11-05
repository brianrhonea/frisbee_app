import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/username.dart';
import '../../../utils/password_policy.dart';
import '../../../utils/result.dart';
import '../../services/account_service.dart';
import '../../services/auth_service.dart';
import '../../services/shared_streams.dart';
import 'auth_repository.dart';

class AuthRepositoryFirebase extends AuthRepository {
  AuthRepositoryFirebase({
    required AuthService authService,
    required AccountService accountService,
    FirebaseFirestore? firestore,
  }) : _authService = authService,
       _accounts = accountService,
       _firestore = firestore ?? FirebaseFirestore.instance {
    _subscription = _authService.userChanges().listen(_onUserChanged);
  }

  final AuthService _authService;
  final AccountService _accounts;
  final FirebaseFirestore _firestore;
  final _log = Logger('AuthRepository');
  late final StreamSubscription<User?> _subscription;

  AppUser? _currentUser;
  bool _isReady = false;

  /// The signed-in user's profile, watched for their username.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  String? _profileUid;
  String? _username;
  Timer? _profileTimeout;

  /// Whether the profile has been read (or we gave up waiting).
  bool _profileKnown = false;

  /// Gave up waiting for the profile (offline on a new device): don't ask
  /// for a username we may already have.
  bool _profileUnknown = false;

  /// A username is being claimed; don't ask for one meanwhile.
  bool _claiming = false;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  bool get isReady => _isReady && (_currentUser == null || _profileKnown);

  @override
  bool get needsUsername =>
      _currentUser != null &&
      _profileKnown &&
      !_profileUnknown &&
      !_claiming &&
      _username == null;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _firestore.collection('profiles');

  void _watchProfile(String? uid) {
    if (uid == _profileUid) return;
    _profileSub?.cancel();
    _profileTimeout?.cancel();
    _profileUid = uid;
    _username = null;
    _profileKnown = uid == null;
    _profileUnknown = false;
    if (uid == null) return;
    _profileTimeout = Timer(const Duration(seconds: 6), () {
      if (_profileKnown) return;
      _profileKnown = true;
      _profileUnknown = true;
      notifyListeners();
    });
    _profileSub = _profiles
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snap) {
            // A missing profile in the cache may just not be synced yet.
            if (!snap.exists && snap.metadata.isFromCache) return;
            _profileTimeout?.cancel();
            // A username is set once and never removed (firestore.rules),
            // so keep the one we know: a snapshot without it is a local
            // write half applied (the Windows SDK sends one while the
            // privacy switch's batch goes out), not the user losing it.
            final username = snap.data()?['username'] as String? ?? _username;
            final changed = username != _username || !_profileKnown;
            _username = username;
            _profileKnown = true;
            _profileUnknown = false;
            if (!changed) return;
            final user = _currentUser;
            if (user != null && user.username != username) {
              final next = user.withUsername(username);
              _currentUser = next;
              // Index the username for search.
              if (username != null) unawaited(_upsertProfile(next));
            }
            notifyListeners();
          },
          onError: (Object e) {
            _log.warning('Profile watch failed', e);
            _profileTimeout?.cancel();
            _profileKnown = true;
            _profileUnknown = true;
            notifyListeners();
          },
        );
  }

  void _onUserChanged(User? user) {
    _watchProfile(user?.uid);
    final next = user == null
        ? null
        : AppUser(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
            photoUrl: user.photoURL,
            username: _username,
          );
    if (next == _currentUser && _isReady) return;
    // Shared listeners belong to the old user; drop them so the next
    // user's screens open their own.
    if (next?.uid != _currentUser?.uid) SharedStreams.instance.clear();
    _currentUser = next;
    _isReady = true;
    if (next != null) unawaited(_upsertProfile(next));
    notifyListeners();
  }

  Future<void> _upsertProfile(AppUser user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'email': user.email,
        'displayName': user.displayName,
        'photoUrl': user.photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // The public directory listing for direct messages: name and photo,
      // never the email. Users without a display name aren't listed.
      final name = user.displayName?.trim() ?? '';
      if (name.isNotEmpty) {
        await _firestore.collection('profiles').doc(user.uid).set({
          ...UserProfile(
            uid: user.uid,
            name: name,
            photoUrl: user.photoUrl,
            username: user.username,
          ).toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
          // Merge: the player's profile details and stats live here too.
        }, SetOptions(merge: true));
      }
    } on Exception catch (e) {
      _log.warning('Failed to save user profile', e);
    }
  }

  @override
  Future<Result<void>> signInWithEmail(String email, String password) =>
      guard(() => _authService.signInWithEmail(email.trim(), password));

  @override
  Future<Result<void>> signIn(String emailOrUsername, String password) =>
      guard(() async {
        final id = emailOrUsername.trim();
        final email = isEmail(id)
            ? id
            : await _accounts.emailForUsername(id, password);
        await _authService.signInWithEmail(email, password);
      });

  @override
  Future<Result<void>> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String username,
  }) => guard(() async {
    final handle = Username.normalize(username);
    if (Username.problem(handle) case final problem?) {
      throw ArgumentError(problem);
    }
    if (!await _available(handle)) throw UsernameTakenException(handle);
    _claiming = true;
    try {
      final first = firstName.trim();
      final last = lastName.trim();
      final user = await _authService.signUpWithEmail(
        email.trim(),
        password,
        '$first $last'.trim(),
      );
      _onUserChanged(user);
      // Private: only they read users/{uid}.
      await _firestore.collection('users').doc(user.uid).set({
        'firstName': first,
        'lastName': last,
      }, SetOptions(merge: true));
      // If it was taken meanwhile, the app asks for another.
      final claimed = await claimUsername(handle);
      if (claimed case Error(:final error)) {
        _log.info('Username claim after sign-up failed', error);
      }
    } finally {
      _claiming = false;
      notifyListeners();
    }
  });

  Future<bool> _available(String username) async {
    try {
      return !(await _firestore.collection('usernames').doc(username).get())
          .exists;
    } on FirebaseException catch (e) {
      // Signed out (the sign-up form), the rules only let you read a name
      // nobody has, so a refusal means it's taken.
      if (e.code == 'permission-denied' && _currentUser == null) return false;
      rethrow;
    }
  }

  @override
  Future<Result<bool>> isUsernameAvailable(String username) => guard(() async {
    final handle = Username.normalize(username);
    if (Username.problem(handle) != null) return false;
    return _available(handle);
  });

  @override
  Future<Result<void>> claimUsername(String username) => guard(() async {
    final user = _currentUser;
    if (user == null) throw StateError('Not signed in');
    final handle = Username.normalize(username);
    if (Username.problem(handle) case final problem?) {
      throw ArgumentError(problem);
    }
    final nameRef = _firestore.collection('usernames').doc(handle);
    final profileRef = _profiles.doc(user.uid);
    // Never list an email as someone's name.
    final display = user.displayName?.trim() ?? '';
    await _firestore.runTransaction((tx) async {
      if ((await tx.get(nameRef)).exists) {
        throw UsernameTakenException(handle);
      }
      tx
        ..set(nameRef, {
          'uid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        })
        ..set(profileRef, {
          ...UserProfile(
            uid: user.uid,
            name: display.isEmpty ? handle : display,
            photoUrl: user.photoUrl,
            username: handle,
          ).toMap(),
          'username': handle,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    });
    _username = handle;
    _currentUser = user.withUsername(handle);
    notifyListeners();
  });

  @override
  Future<Result<void>> signInWithGoogle() =>
      guard(_authService.signInWithGoogle);

  @override
  Future<Result<void>> signInWithApple() => guard(_authService.signInWithApple);

  @override
  Future<Result<void>> sendPasswordReset(String email) =>
      guard(() => _authService.sendPasswordReset(email.trim()));

  @override
  Future<Result<void>> updateDisplayName(String name) =>
      guard(() => _authService.updateDisplayName(name.trim()));

  @override
  Future<Result<void>> signOut() => guard(_authService.signOut);

  @override
  SignInMethod? get reauthMethod =>
      _currentUser == null ? null : _authService.reauthMethod;

  @override
  Future<Result<void>> reauthenticate({String? password}) =>
      guard(() => _authService.reauthenticate(password: password));

  @override
  Future<Result<void>> changePassword({
    required String current,
    required String next,
  }) => guard(() async {
    if (PasswordPolicy.problem(next) case final problem?) {
      throw ArgumentError(problem);
    }
    await _authService.changePassword(current: current, next: next);
  });

  /// The `account-deleteAccount` function deletes the user's data across
  /// every team and conversation, then the login; then sign out here.
  @override
  Future<Result<void>> deleteAccount() => guard(() async {
    await _accounts.deleteAccount();
    _signedOutNotice = 'Account deleted successfully';
    try {
      await _authService.signOut();
    } on Exception catch (e) {
      // The login is already gone; the auth state follows on its own.
      _log.warning('Sign-out after deleting the account failed', e);
    }
  });

  String? _signedOutNotice;

  @override
  String? get signedOutNotice => _signedOutNotice;

  @override
  void clearSignedOutNotice() => _signedOutNotice = null;

  @override
  void dispose() {
    _subscription.cancel();
    _profileSub?.cancel();
    _profileTimeout?.cancel();
    super.dispose();
  }
}
