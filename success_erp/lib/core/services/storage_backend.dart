/// Storage-agnostic contract the app's startup/auth flow depends on.
///
/// Keeping this separate from the concrete backend means the sign-in /
/// session-restore logic in `app.dart` can be exercised in tests with a fake,
/// and means swapping the backend (see AGENTS.md §2) does not touch routing.
abstract class StorageBackend {
  /// Restores a previously granted session *and* prepares the data store,
  /// without any user interaction.
  ///
  /// Returns `true` only when the session was restored **and** the data store
  /// is ready to use. Returns `false` when there is genuinely no session to
  /// restore. Throws when a session exists but preparing the store failed
  /// (e.g. no internet) — callers must treat that as a retryable error and
  /// must NOT send the user back to the sign-in screen.
  Future<bool> restoreSession();

  /// True once the data store is genuinely usable — for the OneDrive backend,
  /// once the workbook has been located and its tables reconciled.
  ///
  /// The historic form of the AGENTS.md §9 defect was a silent sign-in that
  /// reported success without ever locating the workbook; every subsequent
  /// read then threw, the startup catch-all swallowed it, and the user was
  /// dropped on Sign-In. Startup asserts this rather than trusting the boolean.
  bool get isReady;

  /// Interactive sign-in followed by data-store preparation.
  Future<void> signIn();

  /// Drops the local session.
  Future<void> signOut();
}
