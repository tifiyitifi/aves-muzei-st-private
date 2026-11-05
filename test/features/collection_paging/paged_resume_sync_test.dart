import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/sync/paged_library_changes.dart';
import 'package:aves/features/collection_paging/sync/paged_resume_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../fake/paged_discoverer.dart';

/// Returning to the foreground is the one moment a mounted view cannot refresh
/// itself: no resolve runs, and the platform may have dropped the change events
/// while the app was away.
void main() {
  setUpAll(setUpAllServices);
  tearDownAll(tearDownAllServices);

  setUp(() async {
    await collectionPagingPrefs.init();
    await collectionPagingPrefs.setEngine(CollectionEngine.paged);
  });

  ({PagedResumeSync sync, FakePagedDiscoverer discoverer, List<String> events, PagedLibraryChanges changes}) build({
    _FakePhase? phase,
    _FakeImportStatus? importStatus,
  }) {
    final discoverer = FakePagedDiscoverer();
    final changes = PagedLibraryChanges();
    final events = <String>[];
    changes.addListener(() => events.add('changed'));
    final sync = PagedResumeSync(
      discovererFactory: () => discoverer,
      // The order is the contract: the counts a page reads have to be right
      // before the page is told to re-read its window.
      reloadSummaries: () async => events.add('reload'),
      changes: changes,
      phase: phase ?? _FakePhase(),
      importStatus: importStatus ?? _FakeImportStatus(),
    );
    return (sync: sync, discoverer: discoverer, events: events, changes: changes);
  }

  group('PagedResumeSync', () {
    test('applied changes refresh the summaries before the views are told', () async {
      final fixture = build();
      fixture.discoverer.applied = 3;

      await fixture.sync.sync();

      expect(fixture.discoverer.calls, 1);
      expect(fixture.events, ['reload', 'changed']);
      expect(fixture.changes.revision, 1);
    });

    test('a quiet generation does nothing', () async {
      final fixture = build();
      fixture.discoverer.applied = 0;

      await fixture.sync.sync();

      expect(fixture.discoverer.calls, 1);
      expect(fixture.events, isEmpty);
      expect(fixture.changes.revision, 0);
    });

    test('a failed sync is swallowed, not published', () async {
      final fixture = build();
      fixture.discoverer.error = StateError('platform reply lost');

      await fixture.sync.sync();

      expect(fixture.discoverer.calls, 1);
      expect(fixture.events, isEmpty);
      expect(fixture.changes.revision, 0);
    });

    test('the import owns discovery while it runs', () async {
      final fixture = build(importStatus: _FakeImportStatus()..importing = true);

      await fixture.sync.sync();

      expect(fixture.discoverer.calls, 0);
    });

    test('browsing a half-filled database is left alone', () async {
      final fixture = build(phase: _FakePhase()..browsing = true);

      await fixture.sync.sync();

      expect(fixture.discoverer.calls, 0);
    });

    test('the in-memory engine refreshes itself', () async {
      await collectionPagingPrefs.setEngine(CollectionEngine.legacy);
      final fixture = build();

      await fixture.sync.sync();

      expect(fixture.discoverer.calls, 0);
    });

    test('a second resume while one runs is dropped', () async {
      final fixture = build();
      fixture.discoverer
        ..applied = 1
        ..gate = Completer<void>();

      final first = fixture.sync.sync();
      await Future<void>.delayed(Duration.zero);
      await fixture.sync.sync();

      expect(fixture.discoverer.calls, 1);
      fixture.discoverer.gate!.complete();
      await first;
      expect(fixture.changes.revision, 1);
    });
  });
}

class _FakePhase extends Fake implements LibraryPhaseController {
  bool browsing = false;

  @override
  bool get isBrowsing => browsing;
}

class _FakeImportStatus extends Fake implements PagedImportStatus {
  bool importing = false;

  @override
  bool get active => importing;
}
