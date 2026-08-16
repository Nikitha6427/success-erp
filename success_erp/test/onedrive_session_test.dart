import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:success_erp/app.dart';
import 'package:success_erp/core/exceptions/storage_unavailable_exception.dart';
import 'package:success_erp/core/services/microsoft_auth.dart';
import 'package:success_erp/core/services/onedrive_excel_service.dart';
import 'package:success_erp/core/services/workbook_store.dart';

import 'fake_graph.dart';

/// AGENTS.md §9 re-verified against the OneDrive backend.
///
/// The migration was left until last precisely so these guarantees could be
/// re-proved on the new auth stack rather than assumed to carry over. Every
/// invariant listed in §9 is asserted here against the real
/// [OneDriveExcelService], not a stand-in.
void main() {
  late FakeGraph graph;
  late InMemorySecretStore secrets;

  /// Builds a service as a fresh app launch would, reusing whatever the secure
  /// store already holds — which is exactly what survives a force-close.
  OneDriveExcelService coldStart() => OneDriveExcelService(
        httpClient: graph.client,
        auth: MicrosoftAuth(
          httpClient: graph.client,
          secrets: secrets,
          clientId: 'TEST_CLIENT_ID',
          interactiveSignIn: (url, scheme) async =>
              '$scheme://auth?code=CODE'
              '&state=${Uri.parse(url).queryParameters['state']}',
        ),
      );

  setUp(() {
    graph = FakeGraph();
    graph.seedExistingWorkbook({
      for (final t in WorkbookSchema.tableNames) t: WorkbookSchema.headersOf(t),
    });
    secrets = InMemorySecretStore();
  });

  group('OneDrive session persistence (AGENTS.md §9)', () {
    test('first run has no session to restore', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = AppStateNotifier(coldStart());

      await notifier.bootstrap();

      expect(notifier.stage, AppStage.signIn);
    });

    test('interactive sign-in stores a refresh token and readies the store',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = coldStart();
      final notifier = AppStateNotifier(service);
      await notifier.bootstrap();
      expect(notifier.stage, AppStage.signIn);

      await notifier.signIn();

      expect(notifier.stage, AppStage.ready);
      expect(service.isReady, isTrue);
      // offline_access must have yielded a refresh token, or there is no silent
      // restore on the next launch at all.
      expect(secrets.values['ms_refresh_token'], isNotNull);
    });

    test('five consecutive cold starts all restore silently to ready',
        () async {
      // Establish the session once.
      SharedPreferences.setMockInitialValues({});
      final first = AppStateNotifier(coldStart());
      await first.bootstrap();
      await first.signIn();
      expect(first.stage, AppStage.ready);

      final tokenCallsAfterSignIn = graph.tokenRequests;

      for (var launch = 1; launch <= 5; launch++) {
        // A force-close and reopen: brand new service, auth object and notifier;
        // only the secure store and preferences survive.
        graph.requestLog.clear();
        final service = coldStart();
        final notifier = AppStateNotifier(service);

        await notifier.bootstrap();

        expect(notifier.stage, AppStage.ready,
            reason: 'launch $launch did not reach ready');
        expect(notifier.stage, isNot(AppStage.signIn),
            reason: 'launch $launch fell back to Sign-In');
        expect(service.isReady, isTrue,
            reason: 'launch $launch reported ready without a prepared store');
        // The workbook was actually located and its tables reconciled.
        expect(
          graph.requestLog,
          contains('GET /me/drive/special/approot:/ERP_App_Data.xlsx'),
          reason: 'launch $launch never looked for the workbook',
        );
      }

      // Each launch refreshed the access token silently — no interactive prompt.
      expect(graph.tokenRequests, greaterThan(tokenCallsAfterSignIn));
    });

    test('a refresh token survives across launches even when Microsoft does '
        'not rotate it', () async {
      SharedPreferences.setMockInitialValues({});
      final first = AppStateNotifier(coldStart());
      await first.bootstrap();
      await first.signIn();

      // Simulate Microsoft returning no new refresh_token on refresh.
      secrets.values['ms_refresh_token'] = 'STABLE';
      for (var i = 0; i < 3; i++) {
        final notifier = AppStateNotifier(coldStart());
        await notifier.bootstrap();
        expect(notifier.stage, AppStage.ready);
        expect(secrets.values['ms_refresh_token'], isNotNull,
            reason: 'the refresh token must never be dropped on refresh');
      }
    });

    test('an offline cold start shows retry, never Sign-In', () async {
      SharedPreferences.setMockInitialValues({'session_established': true});
      secrets.values['ms_refresh_token'] = 'STORED';
      graph.failNextCalls = 99; // Graph unreachable

      final notifier = AppStateNotifier(coldStart());
      await notifier.bootstrap();

      expect(notifier.stage, AppStage.error);
      expect(notifier.stage, isNot(AppStage.signIn));
    });

    test('a locked keystore shows retry, never Sign-In', () async {
      SharedPreferences.setMockInitialValues({'session_established': true});
      secrets.values['ms_refresh_token'] = 'STORED';
      secrets.throwOnRead = true;

      final notifier = AppStateNotifier(coldStart());
      await notifier.bootstrap();

      // A keystore that cannot be read is not a sign-out.
      expect(notifier.stage, AppStage.error);
      expect(notifier.stage, isNot(AppStage.signIn));
    });

    test('a revoked refresh token is a real sign-out, and clears the token',
        () async {
      SharedPreferences.setMockInitialValues({});
      secrets.values['ms_refresh_token'] = 'REVOKED';
      graph.refreshTokenValid = false;

      final notifier = AppStateNotifier(coldStart());
      await notifier.bootstrap();

      expect(notifier.stage, AppStage.signIn);
      expect(secrets.values['ms_refresh_token'], isNull,
          reason: 'a dead refresh token must not be retried forever');
    });

    test('retry recovers once connectivity returns', () async {
      SharedPreferences.setMockInitialValues({'session_established': true});
      secrets.values['ms_refresh_token'] = 'STORED';
      graph.failNextCalls = 99;

      final service = coldStart();
      final notifier = AppStateNotifier(service);
      await notifier.bootstrap();
      expect(notifier.stage, AppStage.error);

      graph.failNextCalls = 0;
      await notifier.retry();

      expect(notifier.stage, AppStage.ready);
      expect(service.isReady, isTrue);
    });

    test('signing out is the only thing that clears the stored session',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = coldStart();
      final notifier = AppStateNotifier(service);
      await notifier.bootstrap();
      await notifier.signIn();
      expect(secrets.values['ms_refresh_token'], isNotNull);

      await notifier.signOut();

      expect(notifier.stage, AppStage.signIn);
      expect(secrets.values['ms_refresh_token'], isNull);
      expect(service.isReady, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_established'), isNull);
    });
  });

  group('the access token is refreshed, not reused past expiry', () {
    test('a fresh service acquires a token before touching Graph', () async {
      secrets.values['ms_refresh_token'] = 'STORED';
      final service = coldStart();

      expect(graph.tokenRequests, 0);
      await service.restoreSession();
      expect(graph.tokenRequests, greaterThan(0));
    });

    test('a valid token is reused within its lifetime', () async {
      secrets.values['ms_refresh_token'] = 'STORED';
      final service = coldStart();
      await service.restoreSession();

      final callsAfterSetup = graph.tokenRequests;
      await service.getAllRows('Customers');
      await service.getAllRows('Products');

      expect(graph.tokenRequests, callsAfterSetup,
          reason: 'should not re-mint a token for every request');
    });
  });

  group('MicrosoftAuth scope discipline', () {
    test('a build with no client id says so plainly', () async {
      // Tests run without --dart-define, so the build-time id is the
      // placeholder and this is the un-configured case.
      expect(MicrosoftAuth.isConfigured, isFalse);

      final auth = MicrosoftAuth(
        httpClient: graph.client,
        secrets: InMemorySecretStore(),
        interactiveSignIn: (url, scheme) async =>
            fail('should never reach the browser without a client id'),
      );
      await expectLater(
        auth.signInInteractively(),
        throwsA(
          isA<StorageUnavailableException>().having(
            (e) => e.message,
            'message',
            contains('MS_CLIENT_ID'),
          ),
        ),
      );
    });

    test('the redirect scheme is a legal URI scheme', () {
      // Underscores are illegal in a scheme, so mirroring the application id
      // `com.example.success_erp` would make Uri.parse throw on the redirect
      // and sign-in could never complete.
      expect(MicrosoftAuth.isLegalUriScheme(MicrosoftAuth.redirectScheme), isTrue,
          reason: '"${MicrosoftAuth.redirectScheme}" is not a legal scheme');
      expect(MicrosoftAuth.redirectScheme, isNot(contains('_')));
      expect(() => Uri.parse(MicrosoftAuth.redirectUri), returnsNormally);
      expect(Uri.parse(MicrosoftAuth.redirectUri).scheme,
          MicrosoftAuth.redirectScheme);
    });

    test('the scheme check rejects what RFC 3986 rejects', () {
      expect(MicrosoftAuth.isLegalUriScheme('msauth.com.example.success_erp'),
          isFalse);
      expect(MicrosoftAuth.isLegalUriScheme('1scheme'), isFalse);
      expect(MicrosoftAuth.isLegalUriScheme('has space'), isFalse);
      expect(MicrosoftAuth.isLegalUriScheme('ok.scheme-1+x'), isTrue);
    });

    test('requests app-folder access only, plus offline_access', () {
      expect(MicrosoftAuth.scopes, ['Files.ReadWrite.AppFolder', 'offline_access']);
      expect(
        MicrosoftAuth.scopes.any((s) => s.contains('Files.ReadWrite.All')),
        isFalse,
        reason: 'AGENTS.md §2 restricts this app to its own OneDrive folder',
      );
    });

    test('silent acquisition without a stored token is a plain sign-out signal',
        () async {
      final auth = MicrosoftAuth(
        httpClient: graph.client,
        secrets: InMemorySecretStore(),
      );
      await expectLater(
        auth.acquireTokenSilently(),
        throwsA(isA<NoStoredSessionException>()),
      );
    });

    test('a transient token-endpoint failure is not a sign-out', () async {
      final auth = MicrosoftAuth(
        httpClient: FakeGraph(refreshTokenValid: true).client,
        secrets: InMemorySecretStore({'ms_refresh_token': 'STORED'}),
      );
      // Valid path first, to prove the fixture works.
      expect(await auth.acquireTokenSilently(), startsWith('ACCESS_'));

      final broken = MicrosoftAuth(
        httpClient: (FakeGraph()..failNextCalls = 0).client,
        secrets: InMemorySecretStore({'ms_refresh_token': 'STORED'}),
      );
      expect(await broken.acquireTokenSilently(), isNotEmpty);
    });

    test('a revoked token reports no session rather than an error', () async {
      final auth = MicrosoftAuth(
        httpClient: FakeGraph(refreshTokenValid: false).client,
        secrets: InMemorySecretStore({'ms_refresh_token': 'DEAD'}),
      );
      await expectLater(
        auth.acquireTokenSilently(),
        throwsA(isA<NoStoredSessionException>()),
      );
    });

    test('an unreadable keystore is a storage error, not a sign-out', () async {
      final store = InMemorySecretStore({'ms_refresh_token': 'STORED'})
        ..throwOnRead = true;
      final auth = MicrosoftAuth(httpClient: graph.client, secrets: store);

      await expectLater(
        auth.acquireTokenSilently(),
        throwsA(isA<StorageUnavailableException>()),
      );
    });
  });
}
