import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/collection_paging/query/stack_window_filter.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter/foundation.dart';

/// Counts how many entries a set of assist conditions would match.
///
/// Advisory only: an SQL-inexpressible condition, or a database that is not
/// ready, reports null and the sheet simply omits the number instead of making
/// the user wait for a whole-library scan.
abstract final class AssistCounter {
  /// [database] is a test seam; production counts through the app-wide store.
  static Future<int?> count(Set<CollectionFilter> filters, {LocalMediaDb? database}) async {
    if (filters.isEmpty) return null;
    try {
      final predicate = countPredicate(filters);
      if (predicate == null) return null;
      final db = database ?? localMediaDb;
      await db.init();
      return await db.countEntries(predicate);
    } catch (_) {
      return null;
    }
  }
  /// The predicate the sheet's number describes.
  ///
  /// It matches what the paged grid shows: the visible range, the hidden filters,
  /// the locked vaults and the stack filter. A count that ignored any of them
  /// would exceed the rows the user gets after applying the condition.
  @visibleForTesting
  static CollectionWindowPredicate? countPredicate(Set<CollectionFilter> filters) {
    final predicate = predicateForFilters(
      VisibleRangeGate.apply(filters),
      hidden: settings.hiddenFilters,
      // A locked vault keeps its rows in the database, so the exclusion has to
      // come from the predicate, exactly as in the paged window.
      lockedVaultDirs: vaults.vaultDirectories.where(vaults.isLocked).toSet(),
    );
    if (predicate == null) return null;
    // A stack counts once, like its tile.
    return withStackFilter(predicate);
  }
}
