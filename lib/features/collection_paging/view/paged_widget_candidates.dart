import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';

const _log = AreaKeyLog('log.collection_paging');

/// Home-widget entry candidates for paged collections.
///
/// The widget must not fully load a huge library just to pick one picture, so
/// it resolves its filters through the paging router: when the collection would
/// be served paged, only a bounded block of the most recent rows is read from
/// the database mirror (tags/precise dates are irrelevant to the widget's
/// random / most-recent pick). Returning null keeps the legacy full load, which
/// is provably safe below the size threshold.
class PagedWidgetCandidates {
  /// Enough rows for a varied random pick without materializing the library.
  static const defaultLimit = 250;

  /// Returns bounded candidates when the widget's collection routes paged, or
  /// null to keep the legacy full load. Never throws: any database or routing
  /// failure (e.g. no database in the widget process) also returns null.
  static Future<List<AvesEntry>?> load({
    required Set<CollectionFilter> filters,
    int limit = defaultLimit,
    LocalMediaDb? database,
    CollectionEngineRouter? router,
  }) async {
    try {
      final decision = await (router ?? const CollectionEngineRouter()).resolve(filters: filters, database: database);
      final predicate = decision.predicate;
      if (decision.route != CollectionRoute.paged || predicate == null) return null;

      final db = database ?? localMediaDb;
      await db.init();
      final window = await db.loadEntryWindow(
        predicate: predicate,
        sort: SortFactor.date,
        reverse: false,
        limit: limit,
        offset: 0,
      );
      // Attach the catalogued dates so `AvesEntrySort.compareByDate` matches the
      // window ordering the widget re-applies.
      final dates = await db.loadDates();
      for (final entry in window) {
        entry.catalogDateMillis = dates[entry.id];
      }
      return window;
    } catch (error, stack) {
      _log.w('paged widget candidates failed, keeping the legacy full load', error, stack);
      return null;
    }
  }
}
