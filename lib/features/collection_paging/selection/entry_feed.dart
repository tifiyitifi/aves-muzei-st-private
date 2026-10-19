import 'dart:async';

import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/selection/selection_mark.dart';
import 'package:aves/features/collection_paging/view/collection_targets.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:collection/collection.dart';

/// Entries per batch. Small enough that one platform call never carries a huge
/// payload, large enough that a whole library costs a handful of queries.
const entryFeedBatchSize = 256;

/// The entries an entry-set action runs on.
///
/// A whole-view selection is a *marker*, not a list: it can cover a million
/// rows, so an action is never handed a materialized set. It asks the feed for
/// bounded batches instead, and for a count it can show.
///
/// The scope is frozen when the feed is created: a row that arrives afterwards
/// is not swept in, even though it matches the same marker.
abstract interface class EntryFeed {
  /// The largest *declared* feed an action that genuinely needs one payload will
  /// take.
  ///
  /// This is a platform limit, not a semantic one: sharing, picking and the
  /// clipboard hand every item to a single OS payload (an Intent's URI list, a
  /// ClipData), which cannot be streamed. The windowed path therefore offers a
  /// bounded version of those three actions only, and says so, instead of
  /// materializing a whole scope. Every other action resolves its scope as a
  /// predicate, a cursor, a fold or a permutation, and has no such limit.
  ///
  /// A materialized feed ignores it: its set is already in memory, so refusing it
  /// protects nothing and would also take these actions away from the legacy
  /// selection.
  static const materializeLimit = 2000;

  /// How many entries the action covers. Declared; never enumerated.
  ///
  /// Counts tiles, so a stack tile hides its members: an action may touch more
  /// rows than this (see [batches]).
  int get count;

  /// Whether the feed is a whole-view declaration rather than an in-memory set.
  bool get declared;

  /// Whether [entry] belongs to the feed, for tile highlighting.
  bool contains(AvesEntry entry);

  /// Bounded batches, in database order, carrying the deep metadata an action
  /// reads (catalog metadata, address, stack members) and already expanded, so a
  /// batch holds what the legacy selection held.
  Stream<List<AvesEntry>> batches();

  /// A representative entry, for dialogs that only need one. Null when empty.
  Future<AvesEntry?> first();

  /// The whole feed, for the few actions that genuinely need one set.
  ///
  /// A [declared] feed throws [EntryFeedTooLargeException] past [limit]: walking
  /// a whole scope into memory is the cost this limit exists to prevent. A
  /// materialized feed returns its set as is, since the set is already held.
  Future<Set<AvesEntry>> materialize({int limit = materializeLimit});
}

/// Thrown when an action that needs one set meets a feed it cannot hold.
class EntryFeedTooLargeException implements Exception {
  final int count;
  final int limit;

  const new(this.count, this.limit);

  @override
  String toString() => '$runtimeType{count: $count, limit: $limit}';
}

/// A feed over entries already in memory: the legacy selection, and the loaded
/// neighbourhood of a windowed collection.
class MaterializedEntryFeed implements EntryFeed {
  final List<AvesEntry> _entries;
  final Set<AvesEntry> _set;

  new(Iterable<AvesEntry> entries) : _entries = List.of(entries), _set = {} {
    _set.addAll(_entries);
  }

  @override
  bool get declared => false;

  @override
  int get count => _entries.length;

  @override
  bool contains(AvesEntry entry) => _set.contains(entry);

  @override
  Stream<List<AvesEntry>> batches() => Stream.fromIterable(_entries.slices(entryFeedBatchSize));

  @override
  Future<AvesEntry?> first() async => _entries.firstOrNull;

  /// The set already held: returned as is, whatever [limit] says.
  ///
  /// A materialized feed is the legacy selection (and the loaded neighbourhood of
  /// a windowed view), so refusing a large one would take actions away from the
  /// legacy path too — the one path whose behaviour must not change.
  @override
  Future<Set<AvesEntry>> materialize({int limit = EntryFeed.materializeLimit}) async => _set;
}

/// The feed an entry-set action runs on.
///
/// Selecting: the marker's declaration on a windowed collection, else the
/// selected entries. Browsing: the whole collection — except on a windowed one,
/// whose `sortedEntries` is a *lazy* list: walking it reads one skeleton per
/// position and kicks a window for each, which on a huge library freezes the UI
/// and hands the action placeholder entries. The loaded neighbourhood is the
/// target set there instead.
///
/// [wholeView] is for an action that covers the view itself rather than a
/// selection ("empty the bin"): the view's scope is declared whole, so a windowed
/// collection does not leave everything past the loaded neighbourhood behind.
EntryFeed entryFeedFor(CollectionLens collection, Selection<AvesEntry> selection, {bool wholeView = false}) {
  if (collection is PagedCollectionLens) {
    if (wholeView) {
      final feed = collection.wholeViewFeed();
      if (feed != null) return feed;
    } else {
      final mark = selection.mark;
      if (mark is CollectionSelectionMark) {
        final feed = collection.declaredFeed(mark);
        if (feed != null) return feed;
      }
    }
  }
  return MaterializedEntryFeed(
    collectionTargetItems(
      collection: collection,
      isSelecting: !wholeView && selection.isSelecting,
      selectedItems: selection.selectedItems,
    ),
  );
}
