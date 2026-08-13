import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final String status;

  const StatusPill({required this.status, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final (bgColor, fgColor) = switch (status) {
      'Pending' => (
        isDark ? const Color(0xFF4E342E) : const Color(0xFFFFF3E0),
        isDark ? const Color(0xFFFFCC80) : const Color(0xFFE65100),
      ),
      'Partially Delivered' => (
        isDark ? const Color(0xFF1A3A5C) : const Color(0xFFE3F2FD),
        isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0),
      ),
      'Delivered' => (
        isDark ? const Color(0xFF1B3A20) : const Color(0xFFE8F5E9),
        isDark ? const Color(0xFFA5D6A7) : const Color(0xFF2E7D32),
      ),
      'Invoiced' => (
        isDark ? const Color(0xFF3A1F4E) : const Color(0xFFF3E5F5),
        isDark ? const Color(0xFFCE93D8) : const Color(0xFF7B1FA2),
      ),
      _ => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurface,
      ),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(status),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          status,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fgColor,
          ),
        ),
      ),
    );
  }
}
