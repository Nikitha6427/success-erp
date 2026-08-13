import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theming/app_theme.dart';
import 'core/services/sheets_service.dart';
import 'features/sign_in/sign_in_screen.dart';
import 'features/setup/setup_screen.dart';
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

enum AppStage { initial, signIn, settingUp, ready, error }

class AppStateNotifier extends ChangeNotifier {
  AppStage _stage = AppStage.initial;
  AppStage get stage => _stage;

  bool _authChecked = false;
  bool get authChecked => _authChecked;

  bool _isSigningIn = false;
  bool get isSigningIn => _isSigningIn;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  final Ref _ref;
  AppStateNotifier(this._ref);

  Future<void> trySilentSignIn() async {
    dev.log('[Auth] === trySilentSignIn START ===');
    _stage = AppStage.initial;
    _authChecked = false;
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 150));

    try {
      final sheetsService = _ref.read(sheetsServiceProvider);
      dev.log('[Auth] Calling signInSilently()...');
      var success = await sheetsService.trySilentReAuth();
      dev.log('[Auth] signInSilently returned: $success');

      // ponytail: if silently fails, try one explicit sign-in with stored session
      // On Linux, google_sign_in_linux may not persist tokens via libsecret,
      // so signInSilently() returns null. Falling back to signIn() shows an
      // account picker popup but completes immediately with cached credentials.
      if (!success) {
        final prefs = await SharedPreferences.getInstance();
        final hadSession = prefs.getBool('has_google_session') ?? false;
        if (hadSession) {
          dev.log('[Auth] Had previous session — trying fallback signIn()...');
          success = await sheetsService.tryExplicitReAuth();
          dev.log('[Auth] Fallback signIn() returned: $success');
        }
      }

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_google_session', true);

        _stage = AppStage.settingUp;
        notifyListeners();
        await sheetsService.runRoundTripTest();
        _authChecked = true;
        _stage = AppStage.ready;
        dev.log('[Auth] Auth SUCCESS → stage=$stage, authChecked=$_authChecked');
        notifyListeners();
        return;
      }
    } catch (e, st) {
      dev.log('[Auth] Auth attempts EXCEPTION: $e\n$st');
    }
    _authChecked = true;
    _stage = AppStage.signIn;
    dev.log('[Auth] All auth attempts failed → stage=$stage, authChecked=$_authChecked');
    notifyListeners();
  }

  Future<void> startSetup() async {
    if (_isSigningIn) return;
    if (_stage == AppStage.settingUp || _stage == AppStage.ready) return;
    _isSigningIn = true;
    _stage = AppStage.settingUp;
    _errorMessage = '';
    notifyListeners();
    try {
      final sheetsService = _ref.read(sheetsServiceProvider);
      await sheetsService.initialize();
      await sheetsService.runRoundTripTest();
      _authChecked = true;
      _stage = AppStage.ready;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_google_session', true);
      dev.log('[Auth] Explicit sign-in successful');
      notifyListeners();
    } catch (e, stack) {
      dev.log('[Auth] Setup error: $e\n$stack');
      _errorMessage = _friendlyError(e);
      _stage = AppStage.error;
      notifyListeners();
    } finally {
      _isSigningIn = false;
    }
  }

  Future<void> retry() async {
    _stage = AppStage.signIn;
    _errorMessage = '';
    notifyListeners();
    await startSetup();
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (msg.contains('429') || msg.contains('quota')) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    if (msg.contains('401') || msg.contains('token') || msg.contains('auth')) {
      return 'Session expired. Please sign in again.';
    }
    if (msg.contains('Sign in cancelled')) {
      return 'Sign in was cancelled.';
    }
    return 'Something went wrong. Please try again.';
  }
}

final appStateProvider =
    ChangeNotifierProvider<AppStateNotifier>((ref) => AppStateNotifier(ref));

final sheetsServiceProvider = Provider<SheetsService>((ref) {
  return SheetsService();
});

final routerProvider = Provider<GoRouter>((ref) {
  final appState = ref.watch(appStateProvider);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: appState,
    redirect: (context, state) {
      final stage = appState.stage;
      final loc = state.matchedLocation;

      // While checking auth silently, stay on setup (splash)
      if (!appState.authChecked) {
        if (loc == '/setup') return null;
        dev.log('[Router] authChecked=false → forcing /setup (was: $loc)');
        return '/setup';
      }

      // Auth check complete — route based on stage
      if (stage != AppStage.ready) {
        if (stage == AppStage.signIn && loc != '/sign-in') {
          dev.log('[Router] stage=signIn → /sign-in (was: $loc)');
          return '/sign-in';
        }
        if (stage == AppStage.settingUp && loc != '/setup') return '/setup';
        if (stage == AppStage.error && loc != '/sign-in') {
          dev.log('[Router] stage=error → /sign-in (was: $loc)');
          return '/sign-in';
        }
      } else {
        if (loc == '/sign-in' || loc == '/setup') {
          dev.log('[Router] stage=ready → / (was: $loc)');
          return '/';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
      GoRoute(path: '/home', builder: (_, _) => const DashboardScreen()),
      GoRoute(
        path: '/customers',
        builder: (_, _) => const CustomerListScreen(),
      ),
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
        builder: (_, state) => CustomerFormScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/products',
        builder: (_, _) => const ProductListScreen(),
      ),
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
        builder: (_, state) =>
            PoDetailScreen(id: state.pathParameters['id']!),
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
        builder: (_, state) {
          final poId = state.uri.queryParameters['poId'];
          return InvoiceFormScreen(poId: poId);
        },
      ),
      GoRoute(
        path: '/invoices',
        builder: (_, _) => const InvoiceListScreen(),
      ),
      GoRoute(
        path: '/invoices/:id',
        builder: (_, state) =>
            InvoiceDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/reports',
        builder: (_, _) => const ReportsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
      ),
    ],
  );
});

class ERPApp extends ConsumerStatefulWidget {
  const ERPApp({super.key});

  @override
  ConsumerState<ERPApp> createState() => _ERPAppState();
}

class _ERPAppState extends ConsumerState<ERPApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(appStateProvider.notifier).trySilentSignIn());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'ERP Manager',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
