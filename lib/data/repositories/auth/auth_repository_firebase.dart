import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/direct_message.dart';
import '../../../utils/result.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_utils.dart';
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
        });
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
  Future<Result<void>> deleteAccount() => guard(() async {
    final uid = _currentUser?.uid;
    if (uid != null) {
      final user = _firestore.collection('users').doc(uid);
      // Client SDKs don't delete subcollections with their parent.
      for (final sub in [
        'events',
        'devices',
        'notifications',
        'settings',
        'follows',
      ]) {
        final docs = (await user.collection(sub).get()).docs;
        await deleteDocs(_firestore, [for (final d in docs) d.reference]);
      }
      // Their posts; a Cloud Function removes each one's photos.
      final posts = await _firestore
          .collection('posts')
          .where('authorId', isEqualTo: uid)
          .get();
      await deleteDocs(_firestore, [for (final d in posts.docs) d.reference]);
      await user.delete();
      await _firestore.collection('profiles').doc(uid).delete();
    }
    await _authService.deleteAccount();
  });

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
