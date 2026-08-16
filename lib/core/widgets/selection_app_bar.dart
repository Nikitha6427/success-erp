import 'package:flutter/material.dart';

/// Contextual app bar shown while a list is in multi-select mode.
///
/// Follows the platform convention: long-press a row to enter selection, tap
/// rows to toggle, close (or the hardware back button — see [SelectionScope])
/// to leave.
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onClose;
  final VoidCallback onToggleSelectAll;

  /// Null while nothing is selected, which also disables the button.
  final VoidCallback? onDelete;

  const SelectionAppBar({
    required this.selectedCount,
    required this.totalCount,
    required this.onClose,
    required this.onToggleSelectAll,
    this.onDelete,
    super.key,
  });

  bool get _allSelected => totalCount > 0 && selectedCount == totalCount;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: theme.colorScheme.secondaryContainer,
      foregroundColor: theme.colorScheme.onSecondaryContainer,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel selection',
        onPressed: onClose,
      ),
      title: Text('$selectedCount selected'),
      actions: [
        IconButton(
          icon: Icon(_allSelected ? Icons.deselect : Icons.select_all),
          tooltip: _allSelected ? 'Clear selection' : 'Select all',
          onPressed: totalCount == 0 ? null : onToggleSelectAll,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete selected',
          color: onDelete == null ? null : theme.colorScheme.error,
          onPressed: onDelete,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Confirmation dialog for a destructive bulk action.
///
/// [consequences] spells out exactly what else goes with it, so the user is
/// never surprised by a cascade.
Future<bool> confirmBulkDelete(
  BuildContext context, {
  required int count,
  required String singular,
  required String plural,
  List<String> consequences = const [],
}) async {
  final label = count == 1 ? singular : '$count $plural';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete $label?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This cannot be undone.'),
          if (consequences.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final line in consequences)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $line'),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Leading widget for a row that participates in selection mode: a checkbox
/// while selecting, the row's normal avatar otherwise.
class SelectionLeading extends StatelessWidget {
  final bool selectionMode;
  final bool selected;
  final Widget child;

  const SelectionLeading({
    required this.selectionMode,
    required this.selected,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!selectionMode) return child;
    final theme = Theme.of(context);
    return CircleAvatar(
      backgroundColor: selected
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHighest,
      foregroundColor: selected
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSurfaceVariant,
      child: Icon(selected ? Icons.check : Icons.circle_outlined),
    );
  }
}
