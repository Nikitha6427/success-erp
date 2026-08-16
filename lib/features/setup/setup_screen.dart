import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Splash shown while a session is being restored and the workbook prepared.
/// This is the app's initial route, so the first frame is never Dashboard and
/// never Sign-In (AGENTS.md §9).
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;
    final shimmerColor = isDark
        ? theme.colorScheme.surfaceContainerLow
        : theme.colorScheme.surfaceContainerLowest;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Shimmer.fromColors(
                  baseColor: surfaceColor,
                  highlightColor: shimmerColor,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/logo.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: surfaceColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: 200,
                        height: 20,
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 280,
                        height: 14,
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Restoring your session…',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Setting up your workspace',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
