import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/models/app_user.dart';
import '../../utils/platform_support.dart';
import 'google_desktop_oauth.dart';

/// Thin wrapper around Firebase Auth that hides per-platform sign-in flows.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    GoogleDesktopOAuth? googleDesktopOAuth,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _googleDesktopOAuth = googleDesktopOAuth ?? GoogleDesktopOAuth();

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final GoogleDesktopOAuth _googleDesktopOAuth;
  bool _googleInitialized = false;

  Stream<User?> userChanges() => _auth.userChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<User> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = cred.user!;
    await user.updateDisplayName(displayName);
    await user.reload();
    return _auth.currentUser ?? user;
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<void> signInWithGoogle() async {
    await _auth.signInWithCredential(await _googleCredential());
  }

  /// How the user confirms it's them: their password if they have one,
  /// else Google, else Apple.
  SignInMethod? get reauthMethod {
    final ids = {
      for (final p in _auth.currentUser?.providerData ?? const <UserInfo>[])
        p.providerId,
    };
    if (ids.contains(EmailAuthProvider.PROVIDER_ID)) {
      return SignInMethod.password;
    }
    if (ids.contains(GoogleAuthProvider.PROVIDER_ID)) {
      return SignInMethod.google;
    }
    if (ids.contains(AppleAuthProvider.PROVIDER_ID)) return SignInMethod.apple;
    return null;
  }

  /// Signs the current user in again, as Firebase requires before deleting
  /// an account. [password] is needed for [SignInMethod.password].
  Future<void> reauthenticate({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in.');
    switch (reauthMethod) {
      case SignInMethod.password:
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: user.email ?? '',
            password: password ?? '',
          ),
        );
      case SignInMethod.google:
        await user.reauthenticateWithCredential(await _googleCredential());
      case SignInMethod.apple:
        await user.reauthenticateWithProvider(AppleAuthProvider());
      case null:
        throw Exception("Your sign-in method can't confirm it's you here.");
    }
  }

  Future<OAuthCredential> _googleCredential() async {
    if (PlatformSupport.desktopGoogleSignIn) {
      final tokens = await _googleDesktopOAuth.signIn();
      return GoogleAuthProvider.credential(
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
    }
    if (!PlatformSupport.nativeGoogleSignIn) {
      throw Exception('Google sign-in is not supported on this platform.');
    }
    if (!_googleInitialized) {
      await _googleSignIn.initialize();
      _googleInitialized = true;
    }
    final account = await _googleSignIn.authenticate();
    return GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
  }

  Future<void> signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    await _auth.signInWithProvider(provider);
  }

  Future<void> updateDisplayName(String name) async {
    await _auth.currentUser?.updateDisplayName(name);
    await _auth.currentUser?.reload();
  }

  Future<void> signOut() async {
    if (_googleInitialized) await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
