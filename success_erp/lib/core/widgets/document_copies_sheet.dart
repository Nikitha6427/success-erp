import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/pdf_common.dart';
import '../services/pdf_share.dart';
import 'snack_bar_helper.dart';

/// Presents the three GST copies of a printed document as three separate PDFs.
///
/// Each row is a standalone file: save/share it on its own, or print just that
/// copy. "Save all three" attaches all three as distinct PDFs rather than one
/// merged document (AGENTS.md §6).
Future<void> showDocumentCopiesSheet(
  BuildContext context, {
  required String title,
  required String documentNumber,
  required List<GeneratedCopy> copies,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _DocumentCopiesSheet(
      title: title,
      documentNumber: documentNumber,
      copies: copies,
    ),
  );
}

class _DocumentCopiesSheet extends StatelessWidget {
  final String title;
  final String documentNumber;
  final List<GeneratedCopy> copies;

  const _DocumentCopiesSheet({
    required this.title,
    required this.documentNumber,
    required this.copies,
  });

  String get _subject => '$title $documentNumber';

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
    String failureLabel,
  ) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context, '$failureLabel: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title $documentNumber', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${copies.length} separate PDFs — one per copy.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _guard(
                context,
                () => PdfShare.shareAll(copies, subject: _subject),
                'Could not save the PDFs',
              ),
              icon: const Icon(Icons.download),
              label: Text('Save all ${copies.length} PDFs'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 8),
            for (final copy in copies)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  child: const Icon(Icons.picture_as_pdf_outlined),
                ),
                title: Text(copy.copy.name),
                subtitle: Text(copy.copy.audience),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download_outlined),
                      tooltip: 'Save this copy',
                      onPressed: () => _guard(
                        context,
                        () => PdfShare.shareOne(copy, subject: _subject),
                        'Could not save this copy',
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.print_outlined),
                      tooltip: 'Print this copy',
                      onPressed: () => _guard(
                        context,
                        () => Printing.layoutPdf(
                          onLayout: (format) async => copy.bytes,
                          name: copy.fileName,
                        ),
                        'Could not print this copy',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
