/// How the collection loads its entries.
///
/// [legacy] (v1) materializes the whole collection in memory, exactly as the
/// upstream code does. [paged] (v2) keeps only the visible windows in memory
/// and resolves the rest from the database on demand, so collections of
/// hundreds of thousands of entries no longer crash on startup.
enum CollectionEngine {
  legacy,
  paged;

  /// The engine a fresh install runs on. Paged loading is the default because
  /// it degrades gracefully to the legacy behaviour for small collections
  /// while staying alive for very large ones.
  static const CollectionEngine defaultEngine = CollectionEngine.paged;

  static CollectionEngine? tryParse(String? name) {
    for (final value in CollectionEngine.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
