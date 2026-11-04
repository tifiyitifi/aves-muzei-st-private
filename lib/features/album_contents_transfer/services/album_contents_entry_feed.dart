import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/collection_paging/selection/declared_entry_feed.dart';
import 'package:aves/features/collection_paging/selection/entry_feed.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:collection/collection.dart';

/// The entries of a set of selected albums, walked from the database.
///
/// An album selection on a windowed library has no entry list to hand over, so
/// this feed is the action's equivalent of the marked-view feed: bounded batches
/// of the scope's rows, frozen at [count].
///
/// Stacks are *not* expanded: the scope is a directory set, and a stack tile's
/// members may live in other albums, which this action must leave alone. The
/// walk yields every row of the scope instead, exactly like a legacy in-memory
/// scan of the visible entries.
class AlbumContentsEntryFeed implements EntryFeed {
  final Set<StoredAlbumFilter> albums;

  /// The scope's predicate, narrowed to the albums whose contents travel.
  final CollectionWindowPredicate predicate;

  /// Rows the action touches: the scope's frozen count.
  @override
  final int count;

  const new({
    required this.albums,
    required this.predicate,
    required this.count,
  });

  @override
  bool get declared => true;

  /// Only asked by grid tile highlighting, which an album action never uses.
  @override
  bool contains(AvesEntry entry) => albums.any((filter) => filter.test(entry));

  @override
  Stream<List<AvesEntry>> batches() => walkEntryBatches(predicate: predicate, count: count, stackEntries: false);

  @override
  Future<AvesEntry?> first() async {
    await for (final batch in batches()) {
      return batch.firstOrNull;
    }
    return null;
  }

  @override
  Future<Set<AvesEntry>> materialize({int limit = EntryFeed.materializeLimit}) async {
    if (count > limit) throw EntryFeedTooLargeException(count, limit);
    final result = <AvesEntry>{};
    await for (final batch in batches()) {
      result.addAll(batch);
      if (result.length > limit) throw EntryFeedTooLargeException(result.length, limit);
    }
    return result;
  }
}
