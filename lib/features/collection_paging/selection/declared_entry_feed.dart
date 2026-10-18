import 'dart:async';
import 'dart:math';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/collection_paging/selection/entry_feed.dart';
import 'package:aves/features/collection_paging/selection/selection_mark.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/common/services.dart';
import 'package:collection/collection.dart';

/// The feed a marked view resolves to: bounded batches walked from the database.
///
/// The scope is frozen when the feed is created — the predicate value, how many
/// tiles it held and how many rows the selection expands to — so a file added
/// while the action runs is never swept in, even though it matches the same
/// marker. The walk is id-ordered and keyset-paged, so a whole library costs one
/// indexed query per batch instead of an offset scan per section.
class DeclaredEntryFeed implements EntryFeed {
  final CollectionSelectionMark mark;

  /// The frozen scope an action walks: the view's tiles with the unmarked rows
  /// excluded.
  final CollectionWindowPredicate tilePredicate;

  /// How many tiles the frozen scope holds. The walk stops after them, which is
  /// what keeps a file added while the action runs out of it.
  final int tileCount;

  /// Rows the action touches: the tiles plus the stack members they hide.
  @override
  final int count;

  final bool stackEntries;

  new({
    required this.mark,
    required this.tilePredicate,
    required this.tileCount,
    required this.count,
    required this.stackEntries,
  });

  @override
  bool get declared => true;

  @override
  bool contains(AvesEntry entry) => mark.isMarked(entry);

  @override
  Stream<List<AvesEntry>> batches() async* {
    var walked = 0;
    var afterId = 0;
    while (walked < tileCount) {
      final rows = await localMediaDb.loadWalkWindow(
        predicate: tilePredicate,
        afterId: afterId,
        limit: min(entryFeedBatchSize, tileCount - walked),
      );
      if (rows.isEmpty) break;
      afterId = rows.last.id;
      walked += rows.length;
      final batch = await materializeFeedBatch(rows, stackEntries: stackEntries);
      if (batch.isNotEmpty) yield batch;
    }
  }

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

/// Attaches the deep metadata a batch needs, then expands its stack tiles.
///
/// A walked row carries what a window row carries, but not the catalog metadata
/// an edit reads (tags, rating, dates) nor the address a location edit reads:
/// without them a batch would edit from an empty base and lose data. Bounded
/// chunks, like every other read here, so a batch costs a few indexed lookups.
Future<List<AvesEntry>> materializeFeedBatch(List<AvesEntry> rows, {required bool stackEntries}) async {
  if (rows.isEmpty) return const [];
  final byId = {for (final row in rows) row.id: row};
  for (final slice in byId.keys.toList().slices(500)) {
    final ids = slice.toSet();
    final metaById = {for (final meta in await localMediaDb.loadCatalogMetadataById(ids)) meta.id: meta};
    final addressById = {for (final address in await localMediaDb.loadAddressesById(ids)) address.id: address};
    final stacksById = stackEntries ? await localMediaDb.loadStackMembers(ids) : const <int, List<AvesEntry>>{};
    for (final id in ids) {
      final row = byId[id];
      if (row == null) continue;
      row.catalogMetadata = metaById[id];
      row.addressDetails = addressById[id];
      final members = stacksById[id];
      // Stack members ride on a new instance: the field is not settable. The
      // list starts with the tile itself, exactly like the legacy selection.
      if (members != null) byId[id] = row.copyWith(stackedEntries: members);
    }
  }
  return [for (final row in byId.values) ...row.stackedEntries ?? {row}];
}
