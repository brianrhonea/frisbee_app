import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/direct_message.dart';
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

  @override
  AppUser? get currentUser => _currentUser;

  @override
  bool get isReady => _isReady;

  void _onUserChanged(User? user) {
    final next = user == null
        ? null
        : AppUser(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
            photoUrl: user.photoURL,
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
  Future<Result<void>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) => guard(() async {
    final user = await _authService.signUpWithEmail(
      email.trim(),
      password,
      displayName.trim(),
    );
    _onUserChanged(user);
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
    super.dispose();
  }
}
