/// Raised when a record cannot be deleted because other records still point at
/// it (AGENTS.md §10).
class ReferentialIntegrityException implements Exception {
  final String message;
  const ReferentialIntegrityException(this.message);

  @override
  String toString() => message;
}
