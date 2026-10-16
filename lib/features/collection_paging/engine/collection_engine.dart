/// How the collection loads its entries.
///
/// [legacy] (v1) materializes the whole collection in memory, exactly as the
/// upstream code does. [paged] (v2) keeps only the visible windows in memory
/// and resolves the rest from the database on demand, so collections of
/// hundreds of thousands of entries no longer crash on startup. [auto]
/// selects [legacy] below the size threshold and [paged] above it, so small
/// libraries keep full filter-grid covers and counts while very large ones
/// stay alive.
enum CollectionEngine {
  legacy,
  paged,
  auto;

  /// The engine a fresh install runs on. Automatic: large collections degrade
  /// to paged loading instead of crashing, small ones keep the legacy
  /// behaviour with zero UI difference.
  static const CollectionEngine defaultEngine = CollectionEngine.auto;

  static CollectionEngine? tryParse(String? name) {
    for (final value in CollectionEngine.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
