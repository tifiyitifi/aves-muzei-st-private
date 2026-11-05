import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/collection_paging/sync/paged_discoverer.dart';
import 'package:aves/features/collection_paging/sync/paged_library_changes.dart';
import 'package:aves/features/collection_paging/sync/platform_timeout.dart';
import 'package:aves/features/logging/log.dart';

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
      final applied = await withPlatformTimeout(_discovererFactory().syncIfChanged, label: 'resume media store sync');
      if (applied == null || applied <= 0) return;
      // Counts first (album/tag/place pages read the summaries), then the live
      // windows, so a view never repaints against a stale total.
      await _reloadSummaries();
      _changes.bump();
      _log.d('resume sync applied $applied changes');
    } finally {
      _running = false;
    }
  }
}

/// The app-wide instance (same singleton style as `collectionPagingPrefs`).
final PagedResumeSync pagedResumeSync = PagedResumeSync();

/// Syncs the windowed library once, on returning to the foreground.
Future<void> syncPagedLibraryOnResume() => pagedResumeSync.sync();
