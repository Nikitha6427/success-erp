import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';

/// Shown when a session exists but the data store could not be reached.
///
/// Deliberately distinct from the Sign-In screen: a network blip must never
/// look like a sign-out (AGENTS.md §9/§10).
class SessionErrorScreen extends ConsumerWidget {
  const SessionErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final isBusy = appState.isSigningIn;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 24),
                Text(
                  "Can't reach your data",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  appState.errorMessage.isNotEmpty
                      ? appState.errorMessage
                      : 'Check your connection and try again.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "You're still signed in to $storageProviderName — nothing "
                  'has been lost.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: isBusy
                      ? null
                      : () => ref.read(appStateProvider.notifier).retry(),
                  icon: isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(isBusy ? 'Retrying…' : 'Try again'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(240, 48),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: isBusy
                      ? null
                      : () =>
                          ref.read(appStateProvider.notifier).forceSignIn(),
                  child: const Text('Sign in with a different account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
