import 'package:flutter/material.dart';
import '../exceptions/conflict_exception.dart';

Future<void> showConflictDialog(BuildContext context, String message) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(Icons.sync_problem, color: Theme.of(context).colorScheme.error, size: 48),
      title: const Text('Conflict Detected'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Returns true if the error was a ConflictException (dialog shown).
/// Returns false if it was some other error (caller should handle).
Future<bool> handleConflictError(BuildContext context, Object error) async {
  if (error is ConflictException) {
    if (context.mounted) {
      await showConflictDialog(context, error.message);
    }
    return true;
  }
  return false;
}
