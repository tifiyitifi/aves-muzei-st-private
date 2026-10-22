import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/logging/log.dart';
import 'package:flutter/foundation.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// Which surface owns the library: the browse-only browser or the collection.
///
/// The app used to answer that question in several places, from different
/// signals (a per-lens flag, the transient import status, a preference that is
/// false until it is loaded). Those signals could disagree for a frame, and a
/// frame is enough to swap the grid for the browser and back: the flicker the
/// user sees, the album list that reads zero, and the browse-only album page
/// that comes back after the import finished all came from that.
///
/// This is the single answer, and it moves one way: once [LibraryPhase.ready],
/// only a new install (or a database reset) can bring browsing back. New photos
/// arrive through the collection's own sync and never touch it.
enum LibraryPhase {
  /// The persisted import flag has not been read yet. Nothing should be
  /// rendered from it: the app awaits [LibraryPhaseController.init] before the
  /// first page, so this is only observable in tests.
  unknown,

  /// The library is not fully imported: rows may still be streaming in.
  importing,

  /// The whole library is in the database; the collection owns the surface.
  ready,

  /// The import stopped with an error. Browsing stays as it is (the database is
  /// partial, so handing it over would show a truncated library as if it were
  /// the whole one) until the user retries.
  failed,
}

class LibraryPhaseController extends ChangeNotifier {
  final CollectionPagingPrefs _prefs;
  final PagedImportStatus _status;

  LibraryPhase _phase = LibraryPhase.unknown;
  bool _failed = false;
  Future<void>? _init;

  /// Whether the phase reached [LibraryPhase.ready] and stays there.
  ///
  /// Everything that reaches this class after the handover — a late status
  /// event, a preference write racing it — must not swap the grid for the
  /// browser again. A database that was emptied under a complete preference is
  /// the one case that has to start over, and it says so through [reopen], not
  /// through one of those signals.
  bool _latched = false;

  /// Incremented when the user asks to resume a failed import; the collection
  /// page watches it and re-runs its lens.
  int _retryToken = 0;

  new({CollectionPagingPrefs? prefs, PagedImportStatus? status})
    : _prefs = prefs ?? collectionPagingPrefs,
      _status = status ?? pagedImportStatus;

  LibraryPhase get phase => _phase;

  /// Whether the browser is the library surface.
  bool get isBrowsing => _phase == LibraryPhase.importing || _phase == LibraryPhase.failed;

  bool get isReady => _phase == LibraryPhase.ready;

  bool get hasFailed => _phase == LibraryPhase.failed;

  int get retryToken => _retryToken;

  /// Reads the persisted flag and starts following the import status. Awaited
  /// by the app setup, so the first page never sees [LibraryPhase.unknown].
  Future<void> init() => _init ??= _initPhase();

  Future<void> _initPhase() async {
    await _prefs.init();
    _prefs.addListener(_recompute);
    _status.addListener(_recompute);
    _recompute();
  }

  /// Records that the import stopped with an error. The surface stays on the
  /// browser: a partial database must not be presented as the library.
  void markFailed() {
    if (_failed) return;
    _failed = true;
    // A failure outranks the handover: a run that broke after the phase already
    // read `ready` (a preference write racing it) left the grid over a partial
    // database.
    _latched = false;
    _recompute();
  }

  /// Resumes a failed import. The retry itself belongs to the lens that owns the
  /// work; this only reopens the phase and tells its page to ask again.
  void retry() {
    if (!_failed) return;
    _failed = false;
    _retryToken++;
    _recompute();
  }

  /// Releases the one-way latch for a database that was emptied under a
  /// preference that says the library is whole.
  ///
  /// The lens owns that evidence (see `PagedCollectionLens._needsImport`): the
  /// marker is written next to the rows, so a missing marker over an empty
  /// database means the rows have to be discovered again, and browsing is what
  /// that looks like. Called while the new run is active, so the phase lands on
  /// [LibraryPhase.importing] and latches back on [LibraryPhase.ready] when the
  /// run ends — a reopening without a run leaves the phase where it was.
  void reopen() {
    _latched = false;
    _recompute();
  }

  void _recompute() {
    // One way. Once the library is whole, nothing brings the browser back —
    // not a late import-status event, not a possibly lost preference. A reset
    // database is not one of those signals: only [reopen] releases the latch.
    if (_latched) return;
    final next = _failed
        ? LibraryPhase.failed
        : _status.active || !_prefs.importComplete
        ? LibraryPhase.importing
        : LibraryPhase.ready;
    // Latch on the reading, not on the transition: a recompute that finds the
    // library already whole must lock it just the same.
    if (next == LibraryPhase.ready) _latched = true;
    if (next == _phase) return;
    _log.i('library phase ${_phase.name} -> ${next.name}');
    _phase = next;
    notifyListeners();
  }
}

/// The app's single library phase (same singleton style as
/// `collectionPagingPrefs`): the lens and the import write it, every surface
/// that has to choose between the browser and the collection reads it.
final LibraryPhaseController libraryPhase = LibraryPhaseController();
