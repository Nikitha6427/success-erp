import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/exceptions/storage_unavailable_exception.dart';
import 'core/theming/app_theme.dart';
import 'core/services/onedrive_excel_service.dart';
import 'core/services/storage_backend.dart';
import 'core/services/workbook_store.dart';
import 'features/sign_in/sign_in_screen.dart';
import 'features/setup/setup_screen.dart';
import 'features/setup/session_error_screen.dart';
import 'features/customers/customer_list_screen.dart';
import 'features/customers/customer_detail_screen.dart';
import 'features/customers/customer_form_screen.dart';
import 'features/products/product_list_screen.dart';
import 'features/products/product_form_screen.dart';
import 'features/purchase_orders/po_list_screen.dart';
import 'features/purchase_orders/po_detail_screen.dart';
import 'features/purchase_orders/po_create_screen.dart';
import 'features/delivery_notes/delivery_form_screen.dart';
import 'features/invoices/invoice_list_screen.dart';
import 'features/invoices/invoice_detail_screen.dart';
import 'features/invoices/invoice_form_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/settings/settings_screen.dart';

/// Startup states. The router derives exactly one destination from each, so a
/// screen can never be rendered before the stage that justifies it.
enum AppStage {
  /// Restoring a session. Renders the splash — never Dashboard, never Sign-In.
  checking,

  /// Genuinely signed out (first run, or the user signed out explicitly).
  signIn,

  /// Signed in, preparing the workbook.
  settingUp,

  /// Signed in and ready.
  ready,

  /// Signed in (or previously signed in) but the data store is unreachable.
  /// A retryable failure — deliberately NOT the sign-in screen.
  error,
}

/// Route locations, centralised so the redirect and the screens can't drift.
class Routes {
  Routes._();
  static const splash = '/setup';
  static const signIn = '/sign-in';
  static const sessionError = '/session-error';
  static const dashboard = '/';
}

/// Persisted marker that a session was successfully established at least once.
///
/// While this is set, a failed silent restore is treated as a *transient*
/// problem (offline, API blip) and routed to the retry screen. Only an explicit
/// sign-out clears it. This is what stops the app dropping the user back on the
/// Sign-In screen after a restart — the recurring defect in AGENTS.md §9.
const String _kSessionEstablishedKey = 'session_established';

class AppStateNotifier extends ChangeNotifier {
  final StorageBackend _backend;
  final Future<SharedPreferences> Function() _prefs;

  AppStateNotifier(
    this._backend, {
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _prefs = prefsLoader ?? SharedPreferences.getInstance;

  AppStage _stage = AppStage.checking;
  AppStage get stage => _stage;

  bool _isSigningIn = false;
  bool get isSigningIn => _isSigningIn;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  /// Number of completed bootstrap attempts — used by tests to assert that a
  /// cold start resolves without ever passing through [AppStage.signIn].
  int bootstrapCount = 0;

  /// Startup diagnostics. AGENTS.md §9 asks for logging around the silent
  /// re-auth and the router's initial decision whenever this area is touched;
  /// keeping it permanently (debug builds only) means the next investigation
  /// starts with evidence instead of guesses.
  static void log(String message) {
    dev.log(message, name: 'Startup');
    assert(() {
      debugPrint('[Startup] $message');
      return true;
    }());
  }

  void _setStage(AppStage next, {String error = ''}) {
    _stage = next;
    _errorMessage = error;
    log('stage -> ${next.name}${error.isEmpty ? '' : ' ($error)'}');
    notifyListeners();
  }

  /// Cold-start path. Runs once per app launch.
  Future<void> bootstrap() async {
    log('bootstrap begin');
    _setStage(AppStage.checking);

    final prefs = await _prefs();
    final hadSession = prefs.getBool(_kSessionEstablishedKey) ?? false;
    log('previously established session: $hadSession');

    try {
      final restored = await _backend.restoreSession();
      log('restoreSession() -> $restored, isReady=${_backend.isReady}');
      if (restored && !_backend.isReady) {
        // Signed in but the store was never prepared: proceeding would render
        // a Dashboard whose every read throws. Surface it instead.
        log('restore reported success but store is not ready');
        _setStage(
          AppStage.error,
          error: 'Signed in, but your ERP workbook could not be opened. '
              'Please try again.',
        );
        bootstrapCount++;
        return;
      }
      if (restored) {
        await prefs.setBool(_kSessionEstablishedKey, true);
        _setStage(AppStage.ready);
        bootstrapCount++;
        return;
      }

      // No session could be restored. If we've never had one, this is a normal
      // first run. If we HAVE had one, silent restore failing is far more
      // likely to be transient than a real sign-out, so offer a retry instead
      // of throwing the user back to Sign-In.
      if (hadSession) {
        _setStage(
          AppStage.error,
          error: 'Could not reconnect to your $storageProviderName account. '
              'Check your connection and try again.',
        );
      } else {
        _setStage(AppStage.signIn);
      }
    } catch (e, st) {
      log('restoreSession() threw: $e');
      dev.log('$st', name: 'Startup');
      _setStage(AppStage.error, error: _friendlyError(e));
    }
    bootstrapCount++;
  }

  /// Interactive sign-in from the Sign-In screen.
  Future<void> signIn() async {
    if (_isSigningIn) return;
    _isSigningIn = true;
    _setStage(AppStage.settingUp);
    try {
      await _backend.signIn();
      if (!_backend.isReady) {
        throw StorageUnavailableException(
          'Signed in, but your ERP workbook could not be opened.',
        );
      }
      final prefs = await _prefs();
      await prefs.setBool(_kSessionEstablishedKey, true);
      _setStage(AppStage.ready);
    } catch (e, st) {
      log('signIn failed: $e');
      dev.log('$st', name: 'Startup');
      final prefs = await _prefs();
      final hadSession = prefs.getBool(_kSessionEstablishedKey) ?? false;
      _setStage(
        hadSession ? AppStage.error : AppStage.signIn,
        error: _friendlyError(e),
      );
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  /// Retry from the session-error screen: try silent restore again first, and
  /// only fall back to interactive sign-in if there is genuinely no session.
  Future<void> retry() async {
    if (_isSigningIn) return;
    _isSigningIn = true;
    _setStage(AppStage.settingUp);
    try {
      final restored = await _backend.restoreSession();
      if (restored && _backend.isReady) {
        final prefs = await _prefs();
        await prefs.setBool(_kSessionEstablishedKey, true);
        _setStage(AppStage.ready);
        return;
      }
      _setStage(
        AppStage.error,
        error: 'Still could not reconnect. You can try again, or sign in with '
            'a different account.',
      );
    } catch (e) {
      _setStage(AppStage.error, error: _friendlyError(e));
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  /// Explicit sign-out — the only thing that clears the established-session
  /// marker and therefore the only path back to the Sign-In screen.
  Future<void> signOut() async {
    try {
      await _backend.signOut();
    } catch (e) {
      log('signOut error (ignored): $e');
    }
    final prefs = await _prefs();
    await prefs.remove(_kSessionEstablishedKey);
    _setStage(AppStage.signIn);
  }

  /// Used by the session-error screen's "use a different account" action.
  Future<void> forceSignIn() async {
    final prefs = await _prefs();
    await prefs.remove(_kSessionEstablishedKey);
    _setStage(AppStage.signIn);
  }

  String _friendlyError(Object e) {
    if (e is StorageUnavailableException) return e.message;
    final msg = e.toString();
    if (msg.contains('SocketException') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Connection refused')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (msg.contains('429') || msg.contains('quota')) {
      return 'Too many requests. Try again in a moment.';
    }
    if (msg.contains('Sign in cancelled')) {
      return 'Sign in was cancelled.';
    }
    return 'Something went wrong. Please try again.';
  }
}

/// Identity provider name, for anything user-facing that has to name it.
const String storageProviderName = 'Microsoft';

/// Where the workbook lives, for anything user-facing that has to name it.
const String storageLocationName = 'OneDrive';

/// The live backend. It is both the row-level store the repositories use and
/// the auth surface startup uses, so there is exactly one of it.
///
/// Swapping clouds means replacing this one provider with another
/// [WorkbookStore] + [StorageBackend] implementation — nothing above the
/// repository layer knows which cloud it is talking to. Keeping that seam is
/// what turned the last backend change into a contained edit rather than a
/// rewrite; don't let a screen or notifier reach past it.
final oneDriveServiceProvider =
    Provider<OneDriveExcelService>((ref) => OneDriveExcelService());

/// Row-level workbook access for repositories.
final workbookStoreProvider = Provider<WorkbookStore>(
  (ref) => ref.watch(oneDriveServiceProvider),
);

/// The startup/auth surface. Overridden with a fake in tests — kept separate
/// from [workbookStoreProvider] so overriding it never forces a cast.
final storageBackendProvider = Provider<StorageBackend>(
  (ref) => ref.watch(oneDriveServiceProvider),
);

final appStateProvider = ChangeNotifierProvider<AppStateNotifier>((ref) {
  final notifier = AppStateNotifier(ref.watch(storageBackendProvider));
  // Kick off immediately at provider creation rather than from a widget's
  // initState, so no frame can be built before the stage is `checking`.
  Future<void>.microtask(notifier.bootstrap);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final appState = ref.watch(appStateProvider);
  return GoRouter(
    // Start on the splash. The Dashboard and the Sign-In screen are only ever
    // reachable once `stage` justifies them.
    initialLocation: Routes.splash,
    refreshListenable: appState,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final target = switch (appState.stage) {
        AppStage.checking || AppStage.settingUp => Routes.splash,
        AppStage.signIn => Routes.signIn,
        AppStage.error => Routes.sessionError,
        AppStage.ready => null,
      };

      if (target != null) {
        if (loc != target) {
          AppStateNotifier.log('router: $loc -> $target '
              '(stage=${appState.stage.name})');
        }
        return loc == target ? null : target;
      }
      // Ready: bounce off any of the pre-auth screens, otherwise stay put.
      if (loc == Routes.signIn ||
          loc == Routes.splash ||
          loc == Routes.sessionError) {
        AppStateNotifier.log('router: $loc -> ${Routes.dashboard} (ready)');
        return Routes.dashboard;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.splash, builder: (_, _) => const SetupScreen()),
      GoRoute(
        path: Routes.sessionError,
        builder: (_, _) => const SessionErrorScreen(),
      ),
      GoRoute(path: Routes.dashboard, builder: (_, _) => const DashboardScreen()),
      GoRoute(path: '/customers', builder: (_, _) => const CustomerListScreen()),
      GoRoute(
        path: '/customers/new',
        builder: (_, _) => const CustomerFormScreen(),
      ),
      GoRoute(
        path: '/customers/:id',
        builder: (_, state) =>
            CustomerDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/customers/:id/edit',
        builder: (_, state) =>
            CustomerFormScreen(id: state.pathParameters['id']),
      ),
      GoRoute(path: '/products', builder: (_, _) => const ProductListScreen()),
      GoRoute(
        path: '/products/new',
        builder: (_, _) => const ProductFormScreen(),
      ),
      GoRoute(
        path: '/products/:id/edit',
        builder: (_, state) => ProductFormScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/purchase-orders',
        builder: (_, _) => const PoListScreen(),
      ),
      GoRoute(
        path: '/purchase-orders/new',
        builder: (_, _) => const PoCreateScreen(),
      ),
      GoRoute(
        path: '/purchase-orders/:id',
        builder: (_, state) => PoDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/purchase-orders/:id/deliver',
        builder: (_, state) =>
            DeliveryFormScreen(poId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/purchase-orders/:id/invoice',
        builder: (_, state) =>
            InvoiceFormScreen(poId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/invoices/new',
        builder: (_, state) =>
            InvoiceFormScreen(poId: state.uri.queryParameters['poId']),
      ),
      GoRoute(path: '/invoices', builder: (_, _) => const InvoiceListScreen()),
      GoRoute(
        path: '/invoices/:id',
        builder: (_, state) =>
            InvoiceDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    ],
  );
});

class ERPApp extends ConsumerWidget {
  const ERPApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ERP Manager',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
