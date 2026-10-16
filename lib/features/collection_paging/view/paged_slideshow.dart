import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/paged_viewer_copy.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/source/collection_source.dart';

/// A window-backed, shuffled slideshow over a paged collection.
///
/// Legacy builds a shuffled snapshot of every entry; on a huge collection that
/// snapshot would materialize the whole library. The session keeps a paged lens
/// whose index space is *not* materialized: the play order is a seeded
/// permutation ([PagedViewerCopy.shuffleSeed]) applied one position at a time,
/// and each position is one `LIMIT 1 OFFSET` read from the database mirror.
///
/// The permutation and the total are frozen when the session opens, so a
/// collection that changes mid-session does not perturb the running order
/// (matching the legacy snapshot, which is equally frozen).
class PagedSlideshowSession {
  final PagedViewerCopy collection;

  /// Owned paged lens backing [collection]; dispose it with [dispose].
  final PagedCollectionLens lens;

  new({required this.collection, required this.lens});

  /// Waits until the first playable position is loaded, so a viewer opens on a
  /// real entry rather than a skeleton.
  Future<void> ready() => collection.prefetchAround(0);

  void dispose() => lens.dispose();
}

/// Slideshow/screen-saver construction shared by both consumers.
class PagedSlideshow {
  /// Opens a window-backed shuffled playlist for [filters], or returns null
  /// when the view must stay legacy (below the size threshold, unsupported
  /// filters, or a database failure) — the caller keeps its existing behaviour.
  static Future<PagedSlideshowSession?> open({
    required CollectionSource source,
    required Set<CollectionFilter> filters,
    required bool skipVideos,
    int? seed,
  }) async {
    // Resolve first: a legacy view never builds a lens, so the small-collection
    // path is byte-for-byte the previous behaviour.
    final decision = await const CollectionEngineRouter().resolve(filters: filters);
    if (decision.route != CollectionRoute.paged) return null;

    final lens = PagedCollectionLens(
      source: source,
      filters: filters,
      // Videos are excluded by the predicate, not by filtering a materialized
      // list, so the total and the permutation both cover non-video entries.
      extraFragments: skipVideos ? [excludeVideoFragment()] : const [],
    );
    await lens.ready;
    if (!lens.pagedActive) {
      // The lens morphed or blocked after all: fall back to the legacy path.
      lens.dispose();
      return null;
    }
    final view = PagedViewerCopy(
      parent: lens,
      // Always shuffled, like the legacy screen saver / slideshow.
      shuffleSeed: seed ?? DateTime.now().millisecondsSinceEpoch,
    );
    return PagedSlideshowSession(collection: view, lens: lens);
  }
}
