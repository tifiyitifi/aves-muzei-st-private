import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/source/collection_lens.dart';

/// Window-backed viewer collection: shares the parent paged lens's live
/// windows instead of snapshotting loaded rows, so swiping past the loaded
/// neighbourhood keeps resolving across the whole collection.
///
/// Reads never block: unloaded positions resolve to the section skeleton (and
/// kick their window, like grid reads). The parent owns every cache; this copy
/// is inert (no subscriptions, no reload) and only forwards listener
/// notifications so the viewer rebuilds when windows fill. It never mutates
/// the shared lists and never disposes shared entries.
class PagedViewerCopy extends CollectionLens {
  final PagedCollectionLens parent;

  bool _disposed = false;

  new({
    required this.parent,
  }) : super(
          source: parent.source,
          filters: parent.filters,
          id: parent.id,
          listenToSource: false,
        ) {
    parent.addListener(_onParentChanged);
  }

  void _onParentChanged() {
    if (!_disposed) notifyListeners();
  }

  bool get parentAlive => parent.lensAlive;

  @override
  bool get isEmpty => entryCount == 0;

  @override
  int get entryCount => parentAlive ? parent.totalCount : 0;

  @override
  List<AvesEntry> get sortedEntries => parentAlive ? parent.liveFlatList : const [];

  /// The entry at [globalIndex], or the section skeleton when its window has
  /// not loaded yet (kicked by the read itself).
  AvesEntry entryAt(int globalIndex) => sortedEntries[globalIndex];

  /// O(1) position of a loaded entry; -1 when evicted or unknown.
  int globalIndexOf(AvesEntry entry) => parentAlive ? parent.liveFlatList.idToGlobal[entry.id] ?? -1 : -1;

  /// Loaded real entries in display order, for actions that must not walk the
  /// lazy list (map, slideshow).
  List<AvesEntry> get loadedEntries => parentAlive ? parent.loadedEntries : const [];

  /// Kicks the windows around [globalIndex] and waits for the drain.
  Future<void> prefetchAround(int globalIndex) => parentAlive ? parent.fillAround(globalIndex) : Future.value();

  /// Walks outward from [from] (exclusive) for a video entry, paging windows
  /// in on demand. Bounded by [maxSteps] index reads so a video-less stretch
  /// cannot stall the UI; a failed window is skipped, collection bounds stop
  /// the walk. Returns the global index, or null.
  Future<int?> findNeighborVideo(int from, int direction, {int maxSteps = 2000}) async {
    assert(direction == 1 || direction == -1);
    var index = from + direction;
    var steps = 0;
    while (steps < maxSteps) {
      if (index < 0 || index >= entryCount) return null;
      var entry = entryAt(index);
      if (entry is SkeletonEntry) {
        await prefetchAround(index);
        if (!parentAlive) return null;
        entry = entryAt(index);
        if (entry is SkeletonEntry) {
          index += direction;
          steps++;
          continue;
        }
      }
      if (entry.isVideo) return index;
      index += direction;
      steps++;
    }
    return null;
  }

  @override
  void refresh() {
    // Inert: the parent owns windows and reloads.
  }

  @override
  void dispose() {
    _disposed = true;
    parent.removeListener(_onParentChanged);
    super.dispose();
  }
}
