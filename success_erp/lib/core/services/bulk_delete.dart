/// Result of deleting several records at once.
///
/// A bulk delete is deliberately partial rather than all-or-nothing: records
/// that are safe to remove go, records that are still referenced are kept and
/// reported back with the reason, so the user isn't blocked by one bad apple
/// and isn't left guessing which ones survived.
class BulkDeleteOutcome {
  /// Ids that were removed.
  final List<String> deleted;

  /// Ids that were kept, mapped to a human-readable reason.
  final Map<String, String> blocked;

  const BulkDeleteOutcome({this.deleted = const [], this.blocked = const {}});

  int get deletedCount => deleted.length;
  int get blockedCount => blocked.length;
  bool get isEmpty => deleted.isEmpty && blocked.isEmpty;

  /// One distinct reason (if they all share one) for a concise message.
  String? get sharedBlockReason {
    final reasons = blocked.values.toSet();
    return reasons.length == 1 ? reasons.first : null;
  }

  /// Message for the snackbar shown after the operation.
  String summary(String singular, String plural) {
    if (isEmpty) return 'Nothing to delete';

    final parts = <String>[];
    if (deletedCount > 0) {
      parts.add('$deletedCount ${deletedCount == 1 ? singular : plural} '
          'deleted');
    }
    if (blockedCount > 0) {
      final reason = sharedBlockReason;
      parts.add(
        '$blockedCount kept${reason == null ? '' : ' — $reason'}',
      );
    }
    return parts.join('  •  ');
  }
}
