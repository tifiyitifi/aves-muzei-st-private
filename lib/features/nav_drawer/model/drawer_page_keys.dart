/// `SharedPreferences` key owned by the navigation-drawer pages slice.
///
/// It lives outside both settings stores (like the settings-engine gate), so the
/// one-time backfill survives a switch between the legacy (v1) and metadata (v2)
/// engines, and an export/import of the settings does not resurrect it.
abstract final class DrawerPageKeys {
  /// Whether a stored drawer page list has already been checked for the legacy
  /// fixed visible-range entry.
  ///
  /// Before the fork pages became editable, the visible range was a fixed tile
  /// that could be neither removed nor added, so every stored list lacks it. The
  /// flag makes the backfill a one-time event: once e.g. the editor has saved the
  /// user's own removals, the missing entry is a decision, not an un-migrated
  /// list.
  static const String forkPagesInitialized = 'nav_drawer.fork_pages_initialized';
}
