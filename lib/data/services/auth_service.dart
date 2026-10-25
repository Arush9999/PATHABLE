import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/configuration.dart';
import '../../backend/supabase_client.dart';

const _googleScopes = ['email', 'profile'];
const _authTimeout = Duration(seconds: 20);

/// Browser origin for Supabase email links and Google OAuth.
///
/// Null off the web so mobile keeps the dashboard deep link. Local web is
/// `http://127.0.0.1:8081` when that is the page that is open.
String? webAuthRedirect({Uri? base, bool? isWeb}) {
  final web = isWeb ?? kIsWeb;
  if (!web) return null;
  return (base ?? Uri.base).origin;
}

/// Turns auth failures into a message the account screen can show.
String describeAuthFailure(
  Object error, {
  Uri? base,
  bool? isWeb,
}) {
  final raw = switch (error) {
    AuthException(:final message) => message,
    PlatformException(:final message, :final code) =>
      (message != null && message.trim().isNotEmpty) ? message : code,
    TimeoutException() =>
      'Sign-in timed out. Check your connection and try again.',
    _ => error.toString(),
  };
  final lower = raw.toLowerCase();
  final redirect = webAuthRedirect(base: base, isWeb: isWeb);
  if (redirect != null &&
      (lower.contains('redirect') || lower.contains('redirect_uri'))) {
    return 'Supabase rejected the redirect to $redirect. Add '
        'http://127.0.0.1:8081 and http://localhost:8081 under '
        'Authentication → URL Configuration → Redirect URLs. $raw';
  }
  return raw;
}

/// Email/password + Google sign-in against Supabase Auth.
///
/// Android and iOS exchange a Google ID token. Flutter web cannot:
/// `google_sign_in` rejects `serverClientId` and does not implement
/// `authenticate()`. Web starts `signInWithOAuth` and returns the browser
/// to [webAuthRedirect].
class AuthService {
  AuthService(this._config);

  final AppConfiguration _config;
  bool _googleInitialized = false;

  SupabaseClient get _client {
    if (!PathAbleSupabase.isInitialized) {
      throw StateError(
        'Supabase is not connected. Set SUPABASE_URL and SUPABASE_ANON_KEY in .env.',
      );
    }
    return PathAbleSupabase.client;
  }

  Session? get currentSession =>
      PathAbleSupabase.isInitialized ? _client.auth.currentSession : null;

  User? get currentUser => currentSession?.user;

  bool get isSignedIn => currentSession != null;

  bool get googleConfigured => _config.hasGoogleSignIn;

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || password.isEmpty) {
      throw const AuthException('Enter your email and password.');
    }
    return _withTimeout(
      _client.auth.signInWithPassword(
        email: trimmedEmail,
        password: password,
      ),
    );
  }

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || password.length < 6) {
      throw const AuthException(
        'Use a valid email and a password of at least 6 characters.',
      );
    }
    return _withTimeout(
      _client.auth.signUp(
        email: trimmedEmail,
        password: password,
        emailRedirectTo: webAuthRedirect(),
        data: {
          if (displayName != null && displayName.trim().isNotEmpty)
            'display_name': displayName.trim(),
        },
      ),
    );
  }

  /// On web, returns null after the browser starts the Google redirect.
  /// On Android and iOS, returns the Supabase session.
  Future<AuthResponse?> signInWithGoogle() async {
    if (!_config.hasGoogleSignIn) {
      throw const AuthException(
        'Google Sign-In is not configured. Add GOOGLE_WEB_CLIENT_ID '
        '(and GOOGLE_IOS_CLIENT_ID on iOS) to .env, and enable the Google '
        'provider in the Supabase Auth dashboard.',
      );
    }
    if (kIsWeb) {
      await _signInWithGoogleOnWeb();
      return null;
    }
    return _signInWithGoogleNative();
  }

  Future<void> signOut() async {
    if (_googleInitialized && !kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (error, stack) {
        debugPrint('Google sign-out ignored: $error\n$stack');
      }
    }
    if (PathAbleSupabase.isInitialized) {
      await _client.auth.signOut();
    }
  }

  Future<void> _signInWithGoogleOnWeb() async {
    final redirectTo = webAuthRedirect();
    if (redirectTo == null || redirectTo.isEmpty) {
      throw const AuthException(
        'Could not determine this site address for Google sign-in.',
      );
    }
    final launched = await _withTimeout(
      _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        scopes: 'openid email profile',
        queryParams: const {'prompt': 'select_account'},
      ),
    );
    if (!launched) {
      throw AuthException(
        'Google sign-in did not open. Add $redirectTo to the Supabase '
        'redirect URL list.',
      );
    }
  }

  Future<AuthResponse> _signInWithGoogleNative() async {
    await _ensureGoogleInitialized();
    GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate(
        scopeHint: _googleScopes,
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Google sign-in was canceled.');
      }
      throw AuthException(
        'Google sign-in failed: ${error.description ?? error.code.name}',
      );
    }

    final authorization =
        await googleUser.authorizationClient.authorizationForScopes(
              _googleScopes,
            ) ??
            await googleUser.authorizationClient.authorizeScopes(_googleScopes);
    final idToken = googleUser.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException(
        'Google did not return an ID token. Check that GOOGLE_WEB_CLIENT_ID '
        'is the OAuth Web client ID from Google Cloud.',
      );
    }

    return _withTimeout(
      _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      ),
    );
  }

  Future<void> _ensureGoogleInitialized() async {
    if (kIsWeb || _googleInitialized) return;
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: _config.googleWebClientId,
        clientId: defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS
            ? _config.googleIosClientId
            : null,
      );
    } on StateError catch (error) {
      if (!error.message.toLowerCase().contains('already')) rethrow;
    }
    _googleInitialized = true;
  }

  Future<T> _withTimeout<T>(Future<T> future) {
    return future.timeout(_authTimeout);
  }
}
