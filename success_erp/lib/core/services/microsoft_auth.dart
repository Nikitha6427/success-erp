import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../exceptions/storage_unavailable_exception.dart';
import 'secret_store.dart';

/// Result of a successful token exchange.
class MicrosoftToken {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  const MicrosoftToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// Treated as expired a minute early so a request never goes out with a token
  /// that dies mid-flight.
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));
}

/// Raised when there is genuinely no session to restore — as opposed to a
/// session that exists but couldn't be refreshed right now.
class NoStoredSessionException implements Exception {
  const NoStoredSessionException();
  @override
  String toString() => 'No stored Microsoft session';
}

/// Microsoft identity platform (v2.0) auth for a public client, using the
/// authorization-code flow with PKCE.
///
/// Implemented directly rather than through an MSAL wrapper because session
/// persistence is the single most defect-prone part of this app (AGENTS.md §9):
/// the refresh token lives in a known place, silent restore is one explicit
/// call, and the whole thing can be driven by a fake HTTP client in tests. A
/// plugin would bury exactly the behaviour that keeps regressing.
class MicrosoftAuth {
  static const String _placeholderClientId =
      'REPLACE_WITH_YOUR_AZURE_APP_CLIENT_ID';

  /// Azure app registration (public client), supplied at build time as
  /// `--dart-define=MS_CLIENT_ID=...` so it is not committed. See README.
  static const String buildTimeClientId = String.fromEnvironment(
    'MS_CLIENT_ID',
    defaultValue: _placeholderClientId,
  );

  /// True when [id] is a real client id rather than the un-configured
  /// placeholder. Checked before sign-in so a misconfigured build says so
  /// plainly instead of failing somewhere inside Microsoft's error pages.
  static bool clientIdIsConfigured(String id) =>
      id.isNotEmpty && id != _placeholderClientId;

  /// Whether THIS build carries a client id.
  static bool get isConfigured => clientIdIsConfigured(buildTimeClientId);

  /// `common` allows both work/school and personal Microsoft accounts.
  static const String tenant = 'common';

  /// Must match, exactly, all three of: the redirect URI registered on the
  /// Azure app registration, the `<data android:scheme>` in
  /// AndroidManifest.xml, and this constant.
  ///
  /// A URI scheme may contain only letters, digits, `+`, `-` and `.` — NOT
  /// underscores. The app's application id is `com.example.success_erp`, so the
  /// obvious "mirror the package name" scheme is illegal and `Uri.parse` on the
  /// redirect throws `FormatException: Illegal scheme character`, which makes
  /// sign-in impossible to complete. Hence `successerp`, not `success_erp`.
static const String redirectScheme = 'successerp';
static const String redirectUri = '$redirectScheme://auth';

  /// Legal-scheme check, per RFC 3986 `scheme = ALPHA *( ALPHA / DIGIT / "+" /
  /// "-" / "." )`.
  static bool isLegalUriScheme(String scheme) =>
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*$').hasMatch(scheme);

  /// App-folder access only — never full OneDrive (AGENTS.md §2).
  /// `offline_access` is what yields a refresh token; without it there is no
  /// silent restore at all and §9 regresses by construction.
  static const List<String> scopes = [
    'Files.ReadWrite.AppFolder',
    'offline_access',
  ];

  static const String _refreshTokenKey = 'ms_refresh_token';

  final http.Client _http;
  final SecretStore _secrets;

  /// [interactiveSignIn] is injectable so the browser hand-off can be faked;
  /// production uses `flutter_web_auth_2`.
  final Future<String> Function(String url, String callbackScheme)
      _interactiveSignIn;

  /// The client id this instance uses. Defaults to the build-time value;
  /// overridable so tests don't need a real registration.
  final String clientId;

  MicrosoftAuth({
    http.Client? httpClient,
    SecretStore? secrets,
    Future<String> Function(String url, String callbackScheme)?
        interactiveSignIn,
    String? clientId,
  })  : _http = httpClient ?? http.Client(),
        _secrets = secrets ?? const SecureSecretStore(),
        _interactiveSignIn = interactiveSignIn ?? _webAuth,
        clientId = clientId ?? buildTimeClientId;

  static Future<String> _webAuth(String url, String callbackScheme) =>
      FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: callbackScheme,
      );

  MicrosoftToken? _token;
  MicrosoftToken? get token => _token;
  bool get hasValidToken => _token != null && !_token!.isExpired;

  String get _authorizeEndpoint =>
      'https://login.microsoftonline.com/$tenant/oauth2/v2.0/authorize';
  String get _tokenEndpoint =>
      'https://login.microsoftonline.com/$tenant/oauth2/v2.0/token';

  // ── Silent restore ────────────────────────────────────────────────────────

  /// Returns a usable access token without any user interaction.
  ///
  /// Throws [NoStoredSessionException] when there is no refresh token to use —
  /// the only condition that should ever send the user to the Sign-In screen.
  /// Throws [StorageUnavailableException] when a refresh token exists but the
  /// exchange failed for a transient reason, which must surface as a retry.
  Future<String> acquireTokenSilently() async {
    if (hasValidToken) return _token!.accessToken;

    final refreshToken = _token?.refreshToken ?? await _readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      dev.log('[MsAuth] no stored refresh token');
      throw const NoStoredSessionException();
    }

    dev.log('[MsAuth] refreshing access token');
    final response = await _postToken({
      'client_id': clientId,
      'scope': scopes.join(' '),
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    });

    return response.accessToken;
  }

  // ── Interactive sign-in ───────────────────────────────────────────────────

  Future<String> signInInteractively() async {
    if (!clientIdIsConfigured(clientId)) {
      throw const StorageUnavailableException(
        'This build has no Microsoft client ID. Rebuild with '
        '--dart-define=MS_CLIENT_ID=<your Azure application client id>.',
      );
    }
    final verifier = _randomUrlSafe(64);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _randomUrlSafe(16);

    final authUrl = Uri.parse(_authorizeEndpoint).replace(queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'response_mode': 'query',
      'scope': scopes.join(' '),
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      // Let Microsoft reuse an existing browser session where it can.
      'prompt': 'consent',
    });

    final result = await _interactiveSignIn(authUrl.toString(), redirectScheme);

    final returned = Uri.parse(result);
    final error = returned.queryParameters['error_description'] ??
        returned.queryParameters['error'];
    if (error != null) throw Exception('Microsoft sign-in failed: $error');

    if (returned.queryParameters['state'] != state) {
      throw Exception('Microsoft sign-in failed: state mismatch');
    }
    final code = returned.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('Microsoft sign-in was cancelled');
    }

    final token = await _postToken({
      'client_id': clientId,
      'scope': scopes.join(' '),
      'code': code,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
      'code_verifier': verifier,
    });
    return token.accessToken;
  }

  Future<void> signOut() async {
    _token = null;
    await _secrets.delete(_refreshTokenKey);
  }

  // ── Token endpoint ────────────────────────────────────────────────────────

  Future<MicrosoftToken> _postToken(Map<String, String> body) async {
    http.Response response;
    try {
      response = await _http.post(
        Uri.parse(_tokenEndpoint),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );
    } catch (e) {
      throw StorageUnavailableException(
        'Could not reach Microsoft sign-in. Check your connection. ($e)',
      );
    }

    if (response.statusCode != 200) {
      final detail = _errorCodeOf(response.body);
      // invalid_grant means the refresh token is genuinely dead (revoked,
      // password changed, consent withdrawn) — that is a real sign-out, so
      // clear it and say so. Anything else is transient.
      if (detail == 'invalid_grant') {
        dev.log('[MsAuth] refresh token rejected (invalid_grant); clearing');
        await signOut();
        throw const NoStoredSessionException();
      }
      throw StorageUnavailableException(
        'Microsoft sign-in returned ${response.statusCode}. '
        'Please try again in a moment.',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    if (accessToken == null) {
      throw const StorageUnavailableException(
        'Microsoft sign-in returned no access token.',
      );
    }
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    // Microsoft may or may not rotate the refresh token; keep the old one when
    // it doesn't, otherwise silent restore breaks on the next launch.
    final refreshToken =
        json['refresh_token'] as String? ?? _token?.refreshToken;

    final token = MicrosoftToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
    _token = token;

    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _secrets.write(_refreshTokenKey, refreshToken);
    }
    return token;
  }

  static String? _errorCodeOf(String body) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>)['error'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readRefreshToken() async {
    try {
      return await _secrets.read(_refreshTokenKey);
    } catch (e) {
      // A locked/unavailable keystore is not a sign-out.
      dev.log('[MsAuth] secure storage unavailable: $e');
      throw StorageUnavailableException('Could not read your saved session ($e)');
    }
  }

  static String _randomUrlSafe(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '').substring(0, length);
  }
}
