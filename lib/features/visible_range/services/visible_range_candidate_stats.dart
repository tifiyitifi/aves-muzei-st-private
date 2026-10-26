import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Advisory preview data of one candidate tile.
@immutable
class VisibleRangeCandidateStats extends Equatable {
  final int? count;
  final AvesEntry? cover;

  const new({this.count, this.cover});

  @override
  List<Object?> get props => [count, cover];
}

/// Counts and cover entries for the candidates shown on the visible-range page.
///
/// The page shows every default, so this is a batch of small queries, not one
/// whole-library load: an SQL-inexpressible filter simply reports null and the
/// tile falls back to its drawn cover. Results are keyed by the filter
/// fingerprint, so candidates that stand for the same conditions share a query.
abstract final class VisibleRangeCandidateStatsLoader {
  static Future<Map<String, VisibleRangeCandidateStats>> load(
    Iterable<Set<CollectionFilter>> filterSets, {
    Set<CollectionFilter>? hidden,
    Set<String>? lockedVaultDirs,
    LocalMediaDb? database,
    void Function(String key, VisibleRangeCandidateStats stats)? onResult,
  }) async {
    final result = <String, VisibleRangeCandidateStats>{};
    final hiddenFilters = hidden ?? settings.hiddenFilters;
    final lockedDirs = lockedVaultDirs ?? vaults.vaultDirectories.where(vaults.isLocked).toSet();
    final db = database ?? localMediaDb;
    try {
      await db.init();
    } catch (_) {
      return result;
    }
    for (final filters in filterSets) {
      final key = filterFingerprint(filters);
      if (result.containsKey(key)) continue;
      final stats = await _loadOne(filters, database: db, hidden: hiddenFilters, lockedVaultDirs: lockedDirs);
      result[key] = stats;
      // Let the page paint each tile as soon as its query returns instead of
      // waiting for the whole batch of defaults.
      onResult?.call(key, stats);
    }
    return result;
  }

  static Future<VisibleRangeCandidateStats> _loadOne(
    Set<CollectionFilter> filters, {
    required LocalMediaDb database,
    required Set<CollectionFilter> hidden,
    required Set<String> lockedVaultDirs,
  }) async {
    try {
      final predicate = predicateForFilters(filters, hidden: hidden, lockedVaultDirs: lockedVaultDirs);
      if (predicate == null) return const VisibleRangeCandidateStats();
      final count = await database.countEntries(predicate);
      final entries = await database.loadEntryWindow(
        predicate: predicate,
        sort: SortFactor.date,
        reverse: false,
        limit: 1,
        offset: 0,
      );
      return VisibleRangeCandidateStats(count: count, cover: entries.firstOrNull);
    } catch (_) {
      // A preview is never worth blocking the page for.
      return const VisibleRangeCandidateStats();
    }
  }
}
