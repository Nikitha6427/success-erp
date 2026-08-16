import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:success_erp/core/exceptions/storage_unavailable_exception.dart';
import 'package:success_erp/core/services/microsoft_auth.dart';

import 'fake_graph.dart';

/// Desktop sign-in runs a real local HTTP server and hands the browser off to
/// [MicrosoftAuth.openBrowser]. These tests substitute a fake browser launcher
/// that performs an *actual* HTTP round-trip against that real loopback server,
/// so the whole flow (bind → redirect URI → code parse → token exchange) is
/// exercised without ever opening a browser on the CI machine.
void main() {
  late FakeGraph graph;
  late InMemorySecretStore secrets;

  /// The authorize URL the fake browser was handed, for assertions.
  late Uri? lastAuthorizeUrl;

  /// Completes only after the loopback server has answered the callback, letting
  /// the test read the "close this tab" page afterwards.
  late Future<http.Response>? lastCallbackResponse;

  /// The user signs in successfully: navigate to the callback with a code and
  /// the correct state. Fire-and-forget — a browser would not wait for the
  /// page either.
  Future<void> completingBrowser(Uri authorizeUrl) async {
    lastAuthorizeUrl = authorizeUrl;
    final redirect = Uri.parse(authorizeUrl.queryParameters['redirect_uri']!);
    final callback = redirect.replace(queryParameters: {
      'code': 'AUTH_CODE',
      'state': authorizeUrl.queryParameters['state'],
    });
    final exchange = http.get(callback);
    lastCallbackResponse = exchange;
    unawaited(exchange);
  }

  Future<void> rejectingBrowser(Uri authorizeUrl) async {
    final redirect = Uri.parse(authorizeUrl.queryParameters['redirect_uri']!);
    unawaited(http.get(redirect.replace(queryParameters: {
      'error': 'access_denied',
      'error_description': 'The user cancelled the prompt',
      'state': authorizeUrl.queryParameters['state'],
    })));
  }

  Future<void> wrongStateBrowser(Uri authorizeUrl) async {
    final redirect = Uri.parse(authorizeUrl.queryParameters['redirect_uri']!);
    unawaited(http.get(redirect.replace(
        queryParameters: {'code': 'AUTH_CODE', 'state': 'WRONG'})));
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    graph = FakeGraph();
    secrets = InMemorySecretStore();
    lastAuthorizeUrl = null;
    lastCallbackResponse = null;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  MicrosoftAuth auth({
    Future<void> Function(Uri url)? browser,
    Duration? timeout,
  }) =>
      MicrosoftAuth(
        httpClient: graph.client,
        secrets: secrets,
        clientId: 'TEST_CLIENT_ID',
        openBrowser: browser,
        loopbackTimeout: timeout ?? const Duration(seconds: 5),
      );

  test('desktop sign-in exchanges the code through the loopback server',
      () async {
    final accessToken =
        await auth(browser: completingBrowser).signInInteractively();

    expect(accessToken, 'ACCESS_1');
    expect(secrets.values['ms_refresh_token'], 'REFRESH_1');

    // The authorize URL used a loopback redirect plus the full OAuth params.
    final authorize = lastAuthorizeUrl!;
    final loopback = authorize.queryParameters['redirect_uri']!;
    expect(loopback, matches(RegExp(r'^http://localhost:\d+$')));
    expect(authorize.scheme, 'https');
    expect(authorize.queryParameters['client_id'], 'TEST_CLIENT_ID');
    expect(authorize.queryParameters['response_type'], 'code');
    expect(authorize.queryParameters['scope'], contains('offline_access'));
    expect(authorize.queryParameters['state'], isNotEmpty);
    expect(authorize.queryParameters['code_challenge'], isNotEmpty);
    expect(authorize.queryParameters['code_challenge_method'], 'S256');

    // The token exchange used the SAME loopback redirect (Microsoft requires
    // authorize and exchange URIs to match exactly).
    final exchange = graph.tokenBodies.single;
    expect(exchange['grant_type'], 'authorization_code');
    expect(exchange['redirect_uri'], loopback);
    expect(exchange['code'], 'AUTH_CODE');

    // The browser got a page telling the user it can close the tab.
    final page = await lastCallbackResponse!;
    expect(page.statusCode, 200);
    expect(page.body, contains('close this tab'));
  });

  test('a state mismatch is rejected without exchanging the code', () async {
    await expectLater(
      auth(browser: wrongStateBrowser).signInInteractively(),
      throwsA(isA<Exception>()
          .having((e) => e.toString(), 'message', contains('state mismatch'))),
    );
    expect(graph.tokenRequests, 0);
  });

  test('denied consent surfaces the Microsoft error', () async {
    await expectLater(
      auth(browser: rejectingBrowser).signInInteractively(),
      throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('The user cancelled'))),
    );
    expect(graph.tokenRequests, 0);
  });

  test('an unreturned browser callback times out with a clear error', () async {
    await expectLater(
      auth(browser: (_) async {}, timeout: const Duration(milliseconds: 50))
          .signInInteractively(),
      throwsA(isA<StorageUnavailableException>()
          .having((e) => e.message, 'message', contains('timed out'))),
    );
  });

  test('the mobile custom-scheme path is untouched on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final mobile = MicrosoftAuth(
      httpClient: graph.client,
      secrets: secrets,
      clientId: 'TEST_CLIENT_ID',
      interactiveSignIn: (url, scheme) async =>
          '$scheme://auth?code=MOBILE&state=${Uri.parse(url).queryParameters['state']}',
      openBrowser: (url) async =>
          fail('the loopback server must not run on Android'),
    );

    await expectLater(mobile.signInInteractively(), completion('ACCESS_1'));
    expect(graph.tokenBodies.single['redirect_uri'], MicrosoftAuth.redirectUri);
  });
}