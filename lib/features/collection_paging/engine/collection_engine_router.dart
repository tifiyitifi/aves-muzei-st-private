import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';

const _logChannel = 'log.collection_paging.router';

const _log = AreaKeyLog(_logChannel);

/// Where a collection view should load from.
enum CollectionRoute {
  /// Full in-memory load, upstream behaviour.
  legacy,

  /// Windowed database reads.
  paged,
}

/// The outcome of routing one collection view.
class EngineDecision {
  /// Load path for the view.
  final CollectionRoute route;

  /// SQL predicate backing the view. Non-null exactly when [route] is paged.
  final CollectionWindowPredicate? predicate;

  /// Fresh total for [predicate], so the lens need not recount before first paint.
  final int total;

  /// Why the legacy path was kept. Null when the paged path was chosen.
  final String? reason;

  const new _({
    required this.route,
    this.predicate,
    required this.total,
    this.reason,
  });

  const new legacy({int total = 0, String? reason}) : this._(route: CollectionRoute.legacy, total: total, reason: reason);

  const new paged({
    required CollectionWindowPredicate predicate,
    required int total,
  }) : this._(route: CollectionRoute.paged, predicate: predicate, total: total);
}

/// Picks the load path for one collection view.
///
/// Rules, in order:
/// 1. Explicit [CollectionEngine.legacy] always wins.
/// 2. Scopes the SQL layer cannot express (anything but empty/album),
///    active hidden filters, locked vaults, and non-Gregorian
///    month/day sections keep the legacy path.
/// 3. Explicit [CollectionEngine.paged] forces the paged path.
/// 4. [CollectionEngine.auto] probes the total and pages at or above the size
///    threshold.
///
/// A failed probe (e.g. a fake database in tests) always falls back to legacy.
class CollectionEngineRouter {
  const new();

  /// Picks the load path for one collection view.
  ///
  /// [database] is the seam under test; production callers omit it and use
  /// the app-wide [localMediaDb].
  Future<EngineDecision> resolve({required Set<CollectionFilter> filters, LocalMediaDb? database}) async {
    final prefs = collectionPagingPrefs;
    await prefs.init();

    if (prefs.engine == CollectionEngine.legacy) {
      return const EngineDecision.legacy(reason: 'engine preference is legacy');
    }

    final predicate = predicateForFilters(
      filters,
      hidden: settings.hiddenFilters,
      // Locked vaults are excluded below anyway; passing them keeps the
      // exclusion fragment correct if that bail is ever relaxed.
      lockedVaultDirs: vaults.vaultDirectories.where(vaults.isLocked).toSet(),
    );
    if (predicate == null) {
      return const EngineDecision.legacy(reason: 'filters need the in-memory path');
    }
    if (vaults.vaultDirectories.any(vaults.isLocked)) {
      return const EngineDecision.legacy(reason: 'locked vaults need the in-memory path');
    }
    final sectionFactor = settings.getEffectiveCollectionSectionFactor(filters);
    if ((sectionFactor == EntrySectionFactor.month || sectionFactor == EntrySectionFactor.day) && settings.calendar != ACalendar.gregorian) {
      return const EngineDecision.legacy(reason: 'non-Gregorian sections need the in-memory path');
    }

    int total;
    try {
      final db = database ?? localMediaDb;
      await db.init();
      total = await db.countEntries(predicate);
    } catch (error, stack) {
      _log.w('paged probe failed, keeping legacy', error, stack);
      return const EngineDecision.legacy(reason: 'paged probe failed');
    }

    if (prefs.engine == CollectionEngine.paged) {
      return EngineDecision.paged(predicate: predicate, total: total);
    }
    if (total >= prefs.largeThreshold) {
      return EngineDecision.paged(predicate: predicate, total: total);
    }
    return EngineDecision.legacy(total: total, reason: 'below the large-collection threshold');
  }
}
