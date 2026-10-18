import 'dart:collection';

import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/collection_paging/query/shuffle_permutation.dart';
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
///
/// With a [shuffleSeed] the copy's index space becomes the *shuffled* order:
/// [entryAt] maps a virtual position through the seeded permutation before
/// reading the parent's list, and [globalIndexOf] maps back. The parent's
/// sectioned windows stay untouched, so a shuffled read is still one window
/// fetch (scattered across sections), which is exactly what a slideshow needs.
class PagedViewerCopy extends CollectionLens {
  final PagedCollectionLens parent;

  /// Seeded shuffle of the index space, or null for the collection's own order.
  final int? shuffleSeed;

  /// When true the copy owns [parent] and disposes it too. Used when the copy
  /// is the only consumer (e.g. a viewer opened from an external intent) and
  /// `EntryViewerPage` disposes the copy it was handed.
  final bool ownsParent;

  bool _disposed = false;

  ShufflePermutation? _permutation;
  int _permutationTotal = -1;
  List<AvesEntry>? _virtualEntries;

  new({
    required this.parent,
    this.shuffleSeed,
    this.ownsParent = false,
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

  /// The permutation over the parent's current total, rebuilt only when the
  /// total changes (the seed is fixed for the copy's lifetime).
  ShufflePermutation? get _permutationFor {
    final seed = shuffleSeed;
    if (seed == null) return null;
    final total = parentAlive ? parent.totalCount : 0;
    if (_permutation == null || _permutationTotal != total) {
      _permutation = ShufflePermutation(seed, total);
      _permutationTotal = total;
    }
    return _permutation;
  }

  @override
  bool get isEmpty => entryCount == 0;

  @override
  int get entryCount => parentAlive ? parent.totalCount : 0;

  /// The parent's live list in its own order (never shuffled).
  List<AvesEntry> get _realEntries => parentAlive ? parent.liveFlatList : const [];

  @override
  List<AvesEntry> get sortedEntries {
    if (_permutationFor == null) return _realEntries;
    return _virtualEntries ??= _VirtualOrderList(this);
  }

  /// The entry at [globalIndex] (a shuffled position when [shuffleSeed] is set),
  /// or the section skeleton when its window has not loaded yet (kicked by the
  /// read itself).
  AvesEntry entryAt(int globalIndex) {
    final permutation = _permutationFor;
    return _realEntries[permutation == null ? globalIndex : permutation.forward(globalIndex)];
  }

  /// O(1) position of a loaded entry; -1 when evicted or unknown. Inverse to
  /// [entryAt], so `entryAt(globalIndexOf(e)) == e` holds under a shuffle too.
  int globalIndexOf(AvesEntry entry) {
    if (!parentAlive) return -1;
    final realIndex = parent.liveFlatList.idToGlobal[entry.id];
    if (realIndex == null) return -1;
    final permutation = _permutationFor;
    return permutation == null ? realIndex : permutation.inverse(realIndex);
  }

  @override
  Future<int> indexOfEntry(AvesEntry entry) async {
    // The parent answers from the database when the row is not loaded; the
    // permutation then maps its real position into this copy's index space.
    final realIndex = await parent.indexOfId(entry.id);
    if (realIndex < 0) return -1;
    final permutation = _permutationFor;
    return permutation == null ? realIndex : permutation.inverse(realIndex);
  }

  @override
  Future<AvesEntry?> firstMatching(bool Function(AvesEntry entry) test) {
    // The copy adds a permutation over the parent's rows, so the parent's
    // database walk answers for both. Inheriting the in-memory scan would walk
    // this copy's lazy list instead, which is the very thing to avoid.
    return parent.firstMatching(test);
  }

  /// Loaded real entries in display order, for actions that must not walk the
  /// lazy list (map, slideshow).
  List<AvesEntry> get loadedEntries => parentAlive ? parent.loadedEntries : const [];

  /// Kicks the windows around [globalIndex] and waits for the drain. The index
  /// is a virtual position when [shuffleSeed] is set, so the fill targets the
  /// real row the caller will read next.
  Future<void> prefetchAround(int globalIndex) {
    if (!parentAlive) return Future.value();
    final permutation = _permutationFor;
    return parent.fillAround(permutation == null ? globalIndex : permutation.forward(globalIndex));
  }

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

  /// Whether a video lies outward from [from] in each direction, for the media
  /// session's skip flags: the same bounded outward search as the viewer's own
  /// next/previous video actions, so the two can never disagree.
  ///
  /// A walk of the lazy list cannot answer this: a position past the loaded
  /// windows reads as a skeleton, which is never a video, so the search would
  /// run to the end of the collection and report "no neighbour".
  Future<({bool previous, bool next})> neighborVideos(int from) async {
    final previous = await findNeighborVideo(from, -1) != null;
    final next = await findNeighborVideo(from, 1) != null;
    return (previous: previous, next: next);
  }

  @override
  void refresh() {
    // Inert: the parent owns windows and reloads.
  }

  @override
  void dispose() {
    _disposed = true;
    parent.removeListener(_onParentChanged);
    if (ownsParent) parent.dispose();
    super.dispose();
  }
}

/// [PagedViewerCopy.sortedEntries] in shuffled order: reads map through the
/// permutation and position lookups use the inverse map, so the list stays
/// consistent with [PagedViewerCopy.entryAt] without materializing anything.
class _VirtualOrderList extends ListBase<AvesEntry> {
  final PagedViewerCopy copy;

  new(this.copy);

  @override
  int get length => copy.entryCount;

  @override
  set length(int value) => throw UnsupportedError('viewer copies are read-only');

  @override
  AvesEntry operator [](int index) => copy.entryAt(index);

  @override
  void operator []=(int index, AvesEntry value) => throw UnsupportedError('viewer copies are read-only');

  @override
  bool contains(Object? element) {
    // Lenient like `PagedFlatList`: any real entry counts as contained, even
    // while its row is evicted, so selection sanitizing never drops it.
    return element is AvesEntry;
  }

  @override
  int indexOf(Object? element, [int start = 0]) {
    if (element is AvesEntry) {
      final index = copy.globalIndexOf(element);
      return index >= start ? index : -1;
    }
    return -1;
  }
}
