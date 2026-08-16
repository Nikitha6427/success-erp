import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:success_erp/app.dart';
import 'package:success_erp/core/exceptions/storage_unavailable_exception.dart';
import 'package:success_erp/core/services/storage_backend.dart';
import 'package:success_erp/features/dashboard/dashboard_screen.dart';
import 'package:success_erp/features/setup/session_error_screen.dart';
import 'package:success_erp/features/setup/setup_screen.dart';
import 'package:success_erp/features/sign_in/sign_in_screen.dart';

/// Stands in for the cloud-backed store so a cold start can be replayed
/// deterministically, independently of any particular backend. AGENTS.md §9
/// requires this path to be proven, not eyeballed once.
///
/// The same guarantees are separately asserted against the real OneDrive
/// service in `onedrive_session_test.dart`.
class FakeBackend implements StorageBackend {
  FakeBackend({
    this.cachedSession = true,
    this.restoreThrows,
    this.prepareStore = true,
  });

  bool cachedSession;
  Object? restoreThrows;

  /// When false, `restoreSession()` reports success without preparing the
  /// store — reproducing the original AGENTS.md §9 failure mode.
  bool prepareStore;

  bool _storeReady = false;
  int restoreCalls = 0;
  int signInCalls = 0;

  @override
  bool get isReady => _storeReady;

  @override
  Future<bool> restoreSession() async {
    restoreCalls++;
    // Real silent auth + workbook lookup is not instantaneous; the delay is
    // what a naive router would render Sign-In through.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (restoreThrows != null) throw restoreThrows!;
    if (cachedSession && prepareStore) _storeReady = true;
    return cachedSession;
  }

  @override
  Future<void> signIn() async {
    signInCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cachedSession = true;
    if (prepareStore) _storeReady = true;
  }

  @override
  Future<void> signOut() async {
    cachedSession = false;
    _storeReady = false;
  }
}

Widget _app(FakeBackend backend) => ProviderScope(
      overrides: [storageBackendProvider.overrideWithValue(backend)],
      child: const ERPApp(),
    );

/// Drives the app forward frame by frame, asserting the Sign-In screen is never
/// on screen at any point.
Future<void> _pumpWithoutSignInFlash(
  WidgetTester tester, {
  required String reason,
}) async {
  expect(find.byType(SignInScreen), findsNothing,
      reason: '$reason: Sign-In visible on the very first frame');
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(find.byType(SignInScreen), findsNothing,
        reason: '$reason: Sign-In flashed at frame $frame');
  }
  await tester.pumpAndSettle();
  expect(find.byType(SignInScreen), findsNothing,
      reason: '$reason: Sign-In visible after settling');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sign-in session persistence (AGENTS.md §9)', () {
    testWidgets(
      'five consecutive cold starts land on Dashboard with zero Sign-In flash',
      (tester) async {
        for (var launch = 1; launch <= 5; launch++) {
          // A force-close/reopen: fresh widget tree, fresh providers, fresh
          // notifier — only the persisted preferences survive, exactly like a
          // real relaunch.
          SharedPreferences.setMockInitialValues({'session_established': true});
          final backend = FakeBackend(cachedSession: true);

          await tester.pumpWidget(_app(backend));

          // First frame must be the splash, never Dashboard and never Sign-In.
          expect(find.byType(SetupScreen), findsOneWidget,
              reason: 'launch $launch: first frame was not the splash');

          await _pumpWithoutSignInFlash(tester, reason: 'launch $launch');

          expect(find.byType(DashboardScreen), findsOneWidget,
              reason: 'launch $launch: did not land on Dashboard');
          expect(backend.signInCalls, 0,
              reason: 'launch $launch: interactive sign-in should never run');

          // Tear the tree down to simulate the process being killed.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets('first ever run shows Sign-In', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final backend = FakeBackend(cachedSession: false);

      await tester.pumpWidget(_app(backend));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(backend.restoreCalls, 1);
    });

    testWidgets(
      'silent restore failing on a known session shows retry, not Sign-In',
      (tester) async {
        // The exact regression: a previously working session fails to restore.
        // Historically this dumped the user on Sign-In.
        SharedPreferences.setMockInitialValues({'session_established': true});
        final backend = FakeBackend(cachedSession: false);

        await tester.pumpWidget(_app(backend));
        await _pumpWithoutSignInFlash(tester, reason: 'silent restore failed');

        expect(find.byType(SessionErrorScreen), findsOneWidget);
      },
    );

    testWidgets(
      'offline store on a known session shows retry, not Sign-In',
      (tester) async {
        SharedPreferences.setMockInitialValues({'session_established': true});
        final backend = FakeBackend(
          restoreThrows:
              StorageUnavailableException('No internet connection.'),
        );

        await tester.pumpWidget(_app(backend));
        await _pumpWithoutSignInFlash(tester, reason: 'offline store');

        expect(find.byType(SessionErrorScreen), findsOneWidget);
        expect(find.text('No internet connection.'), findsOneWidget);
      },
    );

    testWidgets('retry from the error screen recovers to Dashboard',
        (tester) async {
      SharedPreferences.setMockInitialValues({'session_established': true});
      final backend = FakeBackend(
        restoreThrows: StorageUnavailableException('No internet connection.'),
      );

      await tester.pumpWidget(_app(backend));
      await tester.pumpAndSettle();
      expect(find.byType(SessionErrorScreen), findsOneWidget);

      // Connection comes back.
      backend.restoreThrows = null;
      backend.cachedSession = true;

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(SignInScreen), findsNothing);
    });

    testWidgets('explicit sign-out is the only route back to Sign-In',
        (tester) async {
      SharedPreferences.setMockInitialValues({'session_established': true});
      final backend = FakeBackend(cachedSession: true);
      final container = ProviderContainer(
        overrides: [storageBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ERPApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);

      await container.read(appStateProvider.notifier).signOut();
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);

      // And the persisted marker is gone, so the next launch shows Sign-In.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_established'), isNull);
    });
  });

  group('AppStateNotifier', () {
    test('a restored session marks the session as established', () async {
      SharedPreferences.setMockInitialValues({});
      final backend = FakeBackend(cachedSession: true);
      final notifier = AppStateNotifier(backend);

      await notifier.bootstrap();

      expect(notifier.stage, AppStage.ready);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_established'), isTrue);
    });

    test(
        'a session restored without a prepared store is an error, not ready',
        () async {
      // This is the original root cause: silent sign-in succeeded but the
      // workbook was never located, so every later read threw.
      SharedPreferences.setMockInitialValues({'session_established': true});
      final backend = FakeBackend(cachedSession: true, prepareStore: false);
      final notifier = AppStateNotifier(backend);

      await notifier.bootstrap();

      expect(notifier.stage, AppStage.error);
      expect(notifier.stage, isNot(AppStage.ready));
      expect(notifier.stage, isNot(AppStage.signIn));
    });

    test('never reports signIn once a session has been established', () async {
      SharedPreferences.setMockInitialValues({'session_established': true});

      for (final backend in [
        FakeBackend(cachedSession: false),
        FakeBackend(restoreThrows: StorageUnavailableException('offline')),
        FakeBackend(restoreThrows: Exception('SocketException: nope')),
      ]) {
        final notifier = AppStateNotifier(backend);
        await notifier.bootstrap();
        expect(notifier.stage, AppStage.error,
            reason: 'backend $backend should surface a retryable error');
        expect(notifier.stage, isNot(AppStage.signIn));
      }
    });
  });
}
