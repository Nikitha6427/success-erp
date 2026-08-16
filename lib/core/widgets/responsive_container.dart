import 'package:flutter/material.dart';

/// Keeps phone-width layouts exactly as they are, and constrains body content
/// to a readable centered column once the window gets wide (desktop).
///
/// Below [breakpoint] the child is passed through untouched — the same widget
/// tree a phone sees. Above it the child is centered and capped at
/// [maxContentWidth], so form fields and lists stop stretching edge to edge
/// across a full-width desktop window. AppBar, drawer, FAB and window chrome
/// are unaffected; this wraps only the Scaffold body.
class ResponsiveContainer extends StatelessWidget {
  const ResponsiveContainer({required this.child, super.key});

  final Widget child;

  /// Above this width the content is constrained and centered.
  static const double breakpoint = 840;

  /// Ceiling for the content column on wide screens.
  static const double maxContentWidth = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= breakpoint) return child;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: child,
          ),
        );
      },
    );
  }
}