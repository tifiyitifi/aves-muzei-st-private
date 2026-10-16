import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/query/shuffle_permutation.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';

const _log = AreaKeyLog('log.collection_paging');

/// Outcome of resolving a home-widget entry against a paged collection.
///
/// `handled == false` means the caller keeps its legacy full-load path;
/// `handled == true` with a null entry means the paged view is genuinely empty.
typedef WidgetEntryResolution = ({bool handled, AvesEntry? entry});

/// Home-widget entry resolution for paged collections.
///
/// The widget must not fully load a huge library just to pick one picture, so
/// it resolves its filters through the paging router and reads a single row:
/// the most recent one for `mostRecent`, or a seeded-permutation pick for
/// `random` (uniform over the whole collection, no `ORDER BY RANDOM()` scan and
/// no materialized shuffle). Returning `handled: false` keeps the legacy load,
/// which is provably safe below the size threshold.
class PagedWidgetCandidates {
  static Future<WidgetEntryResolution> resolve({
    required Set<CollectionFilter> filters,
    required bool mostRecent,
    int? shuffleSeed,
    LocalMediaDb? database,
    CollectionEngineRouter? router,
  }) async {
    try {
      final decision = await (router ?? const CollectionEngineRouter()).resolve(filters: filters, database: database);
      final predicate = decision.predicate;
      if (decision.route != CollectionRoute.paged || predicate == null) return (handled: false, entry: null);

      final db = database ?? localMediaDb;
      await db.init();
      final total = decision.total;
      if (total <= 0) return (handled: true, entry: null);

      // Random: one virtual position maps to a real index in O(1); the database
      // only serves the row at that offset. Most recent: the first row of the
      // collection order. Either way the returned entry already carries its
      // catalogued date (the window SELECT attaches it).
      final offset = mostRecent ? 0 : ShufflePermutation(shuffleSeed ?? DateTime.now().millisecondsSinceEpoch, total).forward(0);
      final window = await db.loadEntryWindow(predicate: predicate, sort: SortFactor.date, reverse: false, limit: 1, offset: offset);
      return (handled: true, entry: window.isEmpty ? null : window.first);
    } catch (error, stack) {
      _log.w('paged widget entry resolution failed, keeping the legacy full load', error, stack);
      return (handled: false, entry: null);
    }
  }
}
