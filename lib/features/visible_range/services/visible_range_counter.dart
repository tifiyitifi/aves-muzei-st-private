import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';

/// Counts entries for the visible-range page's summary line.
///
/// The count is advisory: an SQL-inexpressible range simply reports null and the
/// page omits the number instead of loading the whole library in memory.
abstract final class VisibleRangeCounter {
  static Future<int?> count(CollectionFilter? filter) async {
    try {
      final predicate = predicateForFilters(
        filter == null ? const <CollectionFilter>{} : {filter},
        hidden: settings.hiddenFilters,
        lockedVaultDirs: vaults.vaultDirectories.where(vaults.isLocked).toSet(),
      );
      if (predicate == null) return null;
      await localMediaDb.init();
      return await localMediaDb.countEntries(predicate);
    } catch (_) {
      return null;
    }
  }

  /// Count for the current gallery range.
  static Future<int?> countCurrent() => count(VisibleRangeGate.filter);

  /// Cumulative counts for the page's steps, in evaluation order.
  static Future<({int? base, int? intermediate, int? total})> counts(VisibleRange range) async {
    final base = await count(range.resolvedBase);
    final intermediate = await count(range.resolvedIntermediate);
    final total = await count(range.resolve());
    return (base: base, intermediate: intermediate, total: total);
  }
}
