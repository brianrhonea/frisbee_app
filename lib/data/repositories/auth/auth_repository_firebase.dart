import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';

import '../../../domain/models/app_user.dart';
import '../../../utils/result.dart';
import '../../services/auth_service.dart';
import 'auth_repository.dart';

class AuthRepositoryFirebase extends AuthRepository {
  AuthRepositoryFirebase({
    required AuthService authService,
    FirebaseFirestore? firestore,
  }) : _authService = authService,
       _firestore = firestore ?? FirebaseFirestore.instance {
    _subscription = _authService.userChanges().listen(_onUserChanged);
  }

  final AuthService _authService;
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
  Future<Result<void>> deleteAccount() => guard(() async {
    final uid = _currentUser?.uid;
    if (uid != null) await _firestore.collection('users').doc(uid).delete();
    await _authService.deleteAccount();
  });

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
