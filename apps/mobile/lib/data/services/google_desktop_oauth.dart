import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google sign-in for desktop platforms that have no native plugin (Windows).
///
/// Runs the OAuth "installed app" flow: opens the system browser, receives
/// the authorization code on a loopback port, and exchanges it (with PKCE)
/// for Google tokens that Firebase Auth accepts as a credential.
///
/// Uses a "Desktop app" OAuth client from Google Cloud. Its ID and secret come
/// from `secrets.local.json` via `--dart-define-from-file`.
class GoogleDesktopOAuth {
  static const _clientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const _clientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
  );

  static bool get isConfigured =>
      _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  /// Returns Google's ID and access tokens for the signed-in account.
  Future<({String idToken, String accessToken})> signIn({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!isConfigured) {
      throw Exception(
        'Google sign-in is not configured. Add GOOGLE_DESKTOP_CLIENT_ID and '
        'GOOGLE_DESKTOP_CLIENT_SECRET to secrets.local.json.',
      );
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final verifier = _randomString(64);
      final state = _randomString(32);
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': _clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'prompt': 'select_account',
      });
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open the browser for Google sign-in.');
      }

      final code = await _awaitCode(server, state).timeout(
        timeout,
        onTimeout: () => throw Exception('Google sign-in timed out.'),
      );
      return _exchangeCode(code, verifier, redirectUri);
    } finally {
      await server.close(force: true);
    }
  }

  Future<String> _awaitCode(HttpServer server, String state) async {
    await for (final request in server) {
      final params = request.uri.queryParameters;
      // Browsers may also ask for /favicon.ico; ignore anything without a
      // response from Google.
      if (!params.containsKey('code') && !params.containsKey('error')) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final ok = params['state'] == state && params['code'] != null;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body style="font-family:sans-serif;text-align:center;'
          'padding-top:4em"><h2>${ok ? 'Signed in' : 'Sign-in failed'}</h2>'
          '<p>You can close this tab and return to the app.</p></body></html>',
        );
      await request.response.close();
      if (params['state'] != state) {
        throw Exception('Google sign-in failed: state mismatch.');
      }
      final error = params['error'];
      if (error != null) {
        throw Exception(
          error == 'access_denied'
              ? 'Google sign-in was cancelled.'
              : 'Google sign-in failed: $error',
        );
      }
      return params['code']!;
    }
    throw Exception('Google sign-in was interrupted.');
  }

  Future<({String idToken, String accessToken})> _exchangeCode(
    String code,
    String verifier,
    String redirectUri,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.https('oauth2.googleapis.com', '/token'),
      );
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        Uri(
          queryParameters: {
            'code': code,
            'client_id': _clientId,
            'client_secret': _clientSecret,
            'redirect_uri': redirectUri,
            'grant_type': 'authorization_code',
            'code_verifier': verifier,
          },
        ).query,
      );
      final response = await request.close();
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      final idToken = body['id_token'] as String?;
      final accessToken = body['access_token'] as String?;
      if (response.statusCode != HttpStatus.ok ||
          idToken == null ||
          accessToken == null) {
        throw Exception(
          'Google sign-in failed: '
          '${body['error_description'] ?? body['error'] ?? response.statusCode}',
        );
      }
      return (idToken: idToken, accessToken: accessToken);
    } finally {
      client.close();
    }
  }

  static String _randomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
