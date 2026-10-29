import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';

/// Counts how many entries a set of assist conditions would match.
///
/// Advisory only: an SQL-inexpressible condition, or a database that is not
/// ready, reports null and the sheet simply omits the number instead of making
/// the user wait for a whole-library scan.
abstract final class AssistCounter {
  static Future<int?> count(Set<CollectionFilter> filters) async {
    if (filters.isEmpty) return null;
    try {
      final predicate = predicateForFilters(VisibleRangeGate.apply(filters), hidden: settings.hiddenFilters);
      if (predicate == null) return null;
      await localMediaDb.init();
      return await localMediaDb.countEntries(predicate);
    } catch (_) {
      return null;
    }
  }
}
