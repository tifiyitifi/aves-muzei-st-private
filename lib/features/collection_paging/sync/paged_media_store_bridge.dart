import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/collection_paging/sync/paged_discoverer.dart';
import 'package:aves/features/collection_paging/sync/paged_library_changes.dart';
import 'package:aves/features/collection_paging/sync/paged_library_ownership.dart';
import 'package:aves/features/collection_paging/sync/platform_timeout.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/utils/debouncer.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// Routes the MediaStore observer to the windowed engine.
///
/// The legacy source answers a store change by re-reading the changed URIs into
/// memory. A database-owned source must not: its rows live in the database, and
/// the generation-gated sync is what brings them forward without materializing
/// the library. The observer stays the same; only the consumer changes.
class PagedMediaStoreBridge {
  final PagedDiscoverer Function() _discovererFactory;
  final Future<void> Function() _reloadSummaries;
  final PagedLibraryChanges _changes;
  final LibraryPhaseController _phase;
  final PagedImportStatus _importStatus;
  final Debouncer _debouncer;

  /// A change arrived that no run has consumed yet.
  bool _pending = false;

  /// Whether a discovery run is in flight.
  bool _running = false;

  new({
    PagedDiscoverer Function()? discovererFactory,
    Future<void> Function()? reloadSummaries,
    PagedLibraryChanges? changes,
    LibraryPhaseController? phase,
    PagedImportStatus? importStatus,
    Duration debounceDelay = ADurations.mediaContentChangeDebounceDelay,
  })  : _discovererFactory = discovererFactory ?? (() => pagedDiscoverer),
        _reloadSummaries = reloadSummaries ?? reloadPagedSummaries,
        _changes = changes ?? pagedLibraryChanges,
        _phase = phase ?? libraryPhase,
        _importStatus = importStatus ?? pagedImportStatus,
        _debouncer = Debouncer(delay: debounceDelay);

  /// Whether this change is the bridge's to consume.
  ///
  /// Answers false for a source the legacy engine owns, so its observer keeps
  /// the in-memory `refreshUris` path untouched.
  bool onStoreChanged(CollectionSource source) {
    if (!pagedLibraryOwnsSource(source)) return false;
    _pending = true;
    _schedule(source);
    return true;
  }

  void _schedule(CollectionSource source) {
    _debouncer(() => unawaited(_drain(source)));
  }

  Future<void> _drain(CollectionSource source) async {
    // The run in flight consumes `_pending` on its next pass; a second one
    // would race it for the same generation.
    if (_running) return;
    _running = true;
    try {
      while (_pending) {
        _pending = false;
        // The import owns discovery while it runs, and browsing means the
        // database is still being filled: neither wants a competing scan.
        if (_phase.isBrowsing || _importStatus.active) return;
        if (!source.canRefresh) {
          // A media operation is moving files: the rows settle when it ends and
          // resumes monitoring. Retry on the same cadence instead of spinning,
          // and keep the change owed so nothing is dropped meanwhile.
          _pending = true;
          _schedule(source);
          return;
        }
        final applied = await withPlatformTimeout(_discovererFactory().syncIfChanged, label: 'media store change sync');
        if (applied == null || applied <= 0) continue;
        // Counts first (album/tag/place pages read the summaries), then the
        // live windows, so a view never repaints against a stale total.
        await _reloadSummaries();
        _changes.bump();
        _log.d('media store change applied $applied changes');
      }
    } finally {
      _running = false;
    }
  }
}

/// The app-wide instance (same singleton style as `collectionPagingPrefs`).
final PagedMediaStoreBridge pagedMediaStoreBridge = PagedMediaStoreBridge();
