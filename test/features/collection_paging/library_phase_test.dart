import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

/// The one-way switch between the browser and the collection.
///
/// The point of these tests is the invariants that used to be broken: browsing
/// while the flag is unset, leaving exactly once, and never coming back on a
/// failure or on new rows.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  setUp(() async {
    await setUpServices();
  });

  late CollectionPagingPrefs prefs;
  late PagedImportStatus status;
  late LibraryPhaseController phase;

  setUp(() async {
    prefs = CollectionPagingPrefs();
    status = PagedImportStatus();
    await prefs.init();
    await prefs.setImportComplete(false);
    phase = LibraryPhaseController(prefs: prefs, status: status);
    await phase.init();
  });

  tearDown(() {
    phase.dispose();
    status.dispose();
    prefs.dispose();
  });

  test('browses until the import flag says the library is whole', () async {
    expect(phase.phase, LibraryPhase.importing);
    expect(phase.isBrowsing, isTrue);

    await prefs.setImportComplete(true);
    expect(phase.phase, LibraryPhase.ready);
    expect(phase.isBrowsing, isFalse);
  });

  test('a late run cannot reopen browsing once the library is whole', () async {
    await prefs.setImportComplete(true);
    expect(phase.phase, LibraryPhase.ready);

    // Terminal. A stray status event, or a preference write racing the handover,
    // must not swap the grid for the browser again: `ready` is the one-way edge
    // that surface choice keys off.
    status.begin(total: 100);
    expect(phase.phase, LibraryPhase.ready);
    expect(phase.isBrowsing, isFalse);

    status.end();
    await prefs.setImportComplete(false);
    expect(phase.phase, LibraryPhase.ready);
    expect(phase.isBrowsing, isFalse);
  });

  test('new rows after a complete import never reopen browsing', () async {
    await prefs.setImportComplete(true);
    expect(phase.isBrowsing, isFalse);

    // A sync reports progress without starting a run: the status drops a report
    // it never began, and the flag is untouched either way.
    status.update(10);
    status.update(11);
    expect(phase.phase, LibraryPhase.ready);
    expect(phase.isBrowsing, isFalse);
  });

  test('a reset database browses again while it is read back', () async {
    await prefs.setImportComplete(true);
    expect(phase.phase, LibraryPhase.ready);

    // The preference outlived the database it describes, and the lens found the
    // rows gone: the browser is what explains the empty collection while
    // MediaStore is walked again, so the one-way edge is the one thing that has
    // to reopen.
    status.begin(total: 2);
    phase.reopen();
    expect(phase.phase, LibraryPhase.importing);
    expect(phase.isBrowsing, isTrue);

    // ...and it latches again once that run is over.
    status.end();
    expect(phase.phase, LibraryPhase.ready);
    expect(phase.isBrowsing, isFalse);
    status.begin(total: 2);
    expect(phase.phase, LibraryPhase.ready, reason: 'a stray run cannot reopen the handover again');
  });

  test('reopening without a run leaves the phase alone', () async {
    await prefs.setImportComplete(true);
    expect(phase.isBrowsing, isFalse);

    // The signal is only meaningful while the new run is active: without one the
    // phase reads the same complete library and stays where it was.
    phase.reopen();
    expect(phase.phase, LibraryPhase.ready);
    expect(phase.isBrowsing, isFalse);
  });

  test('a failed import keeps browsing and clears only on retry', () async {
    await prefs.setImportComplete(false);
    status.begin(total: 100);
    status.end();
    phase.markFailed();
    expect(phase.phase, LibraryPhase.failed);
    expect(phase.hasFailed, isTrue);
    // A failure must not hand a partial database over as the library.
    expect(phase.isBrowsing, isTrue);

    // Progress or a late flag cannot make it look ready.
    status.update(5);
    expect(phase.phase, LibraryPhase.failed);

    final token = phase.retryToken;
    phase.retry();
    expect(phase.retryToken, token + 1);
    expect(phase.phase, LibraryPhase.importing);
    expect(phase.hasFailed, isFalse);
  });
}
