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
}
