import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/collection_paging/sync/paged_discoverer.dart';
import 'package:aves/features/collection_paging/sync/paged_library_changes.dart';
import 'package:aves/features/collection_paging/sync/platform_timeout.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/services/common/services.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// Catches the windowed library up with the MediaStore when the app returns to
/// the foreground.
///
/// A resolve already syncs, but a view that stays mounted never resolves again,
/// so a photo taken in another app would only appear after navigating. The
/// MediaStore change stream should announce it (see the bridge), except during
/// the time the app spends in the background: the platform may drop those
/// events, and the generation check is what makes the return trip cheap when
/// nothing happened.
class PagedResumeSync {
  final PagedDiscoverer Function() _discovererFactory;
  final Future<void> Function() _reloadSummaries;
  final PagedLibraryChanges _changes;
  final LibraryPhaseController _phase;
  final PagedImportStatus _importStatus;

  /// Whether a run is in flight; a second resume lands here and is dropped.
  bool _running = false;

  /// Whether this process already swept the rows the store no longer serves.
  ///
  /// A deletion is final, so one sweep per launch settles it. Repeating the
  /// sweep on every resume would rescan the store each time the user leaves the
  /// app and comes back, for a state nothing can have regressed.
  bool _swept = false;

  /// The sweep reads the whole store, which outlasts a resolve's per-step
  /// budget on a large library.
  static const _sweepTimeout = Duration(seconds: 30);

  new({
    PagedDiscoverer Function()? discovererFactory,
    Future<void> Function()? reloadSummaries,
    PagedLibraryChanges? changes,
    LibraryPhaseController? phase,
    PagedImportStatus? importStatus,
  })  : _discovererFactory = discovererFactory ?? (() => pagedDiscoverer),
        _reloadSummaries = reloadSummaries ?? reloadPagedSummaries,
        _changes = changes ?? pagedLibraryChanges,
        _phase = phase ?? libraryPhase,
        _importStatus = importStatus ?? pagedImportStatus;

  Future<void> sync() async {
    if (_running) return;
    // The import owns discovery while it runs: a sync would race it for the
    // same rows, and browsing means the database is still being filled.
    if (_phase.isBrowsing || _importStatus.active) return;
    if (!collectionPagingPrefs.isLoaded) await collectionPagingPrefs.init();
    // The user chose the in-memory engine, which refreshes itself on resume.
    if (collectionPagingPrefs.engine == CollectionEngine.legacy) return;

    _running = true;
    try {
      final applied = await withPlatformTimeout(_discovererFactory().syncIfChanged, label: 'resume media store sync') ?? 0;
      // The change stream never reports a deletion (see
      // `PagedDiscoverer.reconcileObsoleteMediaStoreRows`), so resuming is also
      // when a row that outlived its file gets its chance to go.
      var removed = 0;
      if (!_swept) {
        final volumePaths = await _mountedVolumePaths();
        final swept = await withPlatformTimeout(
          () => _discovererFactory().reconcileObsoleteMediaStoreRows(mountedVolumePaths: volumePaths),
          label: 'resume obsolete sweep',
          timeout: _sweepTimeout,
        );
        // Only an answered sweep counts as done: a timed-out one retries on the
        // next resume instead of waiting for the next launch.
        _swept = swept != null;
        removed = swept ?? 0;
      }
      if (applied <= 0 && removed <= 0) return;
      // Counts first (album/tag/place pages read the summaries), then the live
      // windows, so a view never repaints against a stale total.
      await _reloadSummaries();
      _changes.bump();
      _log.d('resume sync applied $applied changes, swept $removed obsolete rows');
    } finally {
      _running = false;
    }
  }

  /// The volumes that are mounted right now.
  ///
  /// Asked at sweep time rather than cached: the sweep's whole safety rests on
  /// not asking about a volume the store cannot see, and that changes with the
  /// card. A failure answers empty, which skips the sweep instead of guessing.
  Future<Set<String>> _mountedVolumePaths() async {
    try {
      return {for (final volume in await storageService.getStorageVolumes()) volume.path};
    } catch (error, stack) {
      _log.w('failed to list storage volumes for the obsolete sweep', error, stack);
      return {};
    }
  }
}

/// The app-wide instance (same singleton style as `collectionPagingPrefs`).
final PagedResumeSync pagedResumeSync = PagedResumeSync();

/// Syncs the windowed library once, on returning to the foreground.
Future<void> syncPagedLibraryOnResume() => pagedResumeSync.sync();
