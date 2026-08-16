/// Thrown when the data store could not be reached or prepared even though the
/// user's session itself is fine.
///
/// Deliberately distinct from "not signed in" so the router never falls back to
/// the Sign-In screen for what is really a network blip (AGENTS.md §9).
class StorageUnavailableException implements Exception {
  final String message;
  const StorageUnavailableException(this.message);

  @override
  String toString() => message;
}
