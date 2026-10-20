/// `SharedPreferences` keys owned by the collection paging feature.
///
/// The keys live outside both settings stores (like the settings-engine gate)
/// so they stay readable before a store is chosen and survive switches between
/// the legacy (v1) and metadata (v2) settings engines.
abstract final class CollectionPagingKeys {
  static const String engine = 'collection_paging.engine';

  static const String windowSize = 'collection_paging.window_size';

  static const String prefetchScreens = 'collection_paging.prefetch_screens';

  static const String largeThreshold = 'collection_paging.large_threshold';

  /// Whether the background catalogue asks before sweeping a large backlog.
  static const String askBeforeCatalog = 'collection_paging.ask_before_catalog';

  /// Whether the browse-only notice bar is shown while the import runs.
  ///
  /// On by default: the mode takes features away, so it has to be visible where
  /// the features are, not only in a settings page the user has no reason to
  /// open. Turning it off leaves the app bar subtitle as the only notice.
  static const String browseOnlyBar = 'collection_paging.browse_only_bar';

  /// Whether the one-time "browse first, organize in the background" explainer
  /// has been shown. Kept here, not in a settings store: it must survive a
  /// settings-engine switch and never come back on its own.
  static const String importExplained = 'collection_paging.import_explained';

  /// Whether the library has been fully imported at least once.
  ///
  /// A fresh install, an interrupted first import and a database filled by the
  /// legacy path all read as "not complete", which is exactly the set of cases
  /// that need the (resumable) import to run.
  static const String importComplete = 'collection_paging.import_complete';

  /// Persisted MediaStore generation cursor for change-based sync.
  static const String mediaGeneration = 'collection_paging.media_generation';
}
