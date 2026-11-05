import 'dart:async';

import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/sync/paged_library_changes.dart';
import 'package:aves/features/collection_paging/sync/paged_media_store_bridge.dart';
import 'package:aves/model/source/filter_summary_provider.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../fake/paged_discoverer.dart';

/// A store change on a database-owned source has to reach the engine, not the
/// in-memory re-read the legacy source runs.
void main() {
  const debounce = Duration(milliseconds: 5);

  setUpAll(setUpAllServices);
  tearDownAll(tearDownAllServices);

  late MediaStoreSource source;

  setUp(() {
    source = MediaStoreSource();
  });

  MediaStoreSource pagedSource() => MediaStoreSource()..summaries = _FakeSummaries();

  Future<void> settle({required bool Function() done, required String reason}) async {
    for (var i = 0; i < 200; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail(reason);
  }

  /// Gives a second, unwanted call the chance to show up.
  Future<void> quiet() => Future<void>.delayed(const Duration(milliseconds: 60));

  ({PagedMediaStoreBridge bridge, FakePagedDiscoverer discoverer, List<String> events, PagedLibraryChanges changes}) build({
    _FakePhase? phase,
    _FakeImportStatus? importStatus,
  }) {
    final discoverer = FakePagedDiscoverer();
    final changes = PagedLibraryChanges();
    final events = <String>[];
    changes.addListener(() => events.add('changed'));
    final bridge = PagedMediaStoreBridge(
      discovererFactory: () => discoverer,
      reloadSummaries: () async => events.add('reload'),
      changes: changes,
      phase: phase ?? _FakePhase(),
      importStatus: importStatus ?? _FakeImportStatus(),
      debounceDelay: debounce,
    );
    return (bridge: bridge, discoverer: discoverer, events: events, changes: changes);
  }

  group('PagedMediaStoreBridge', () {
    test('a legacy source keeps its in-memory refresh', () async {
      final fixture = build();
      fixture.discoverer.applied = 1;

      expect(fixture.bridge.onStoreChanged(source), isFalse);
      await quiet();

      expect(fixture.discoverer.calls, 0);
    });

    test('a burst of events costs one sync and publishes once', () async {
      final fixture = build();
      fixture.discoverer.applied = 1;
      final paged = pagedSource();

      for (var i = 0; i < 5; i++) {
        expect(fixture.bridge.onStoreChanged(paged), isTrue);
      }
      await settle(done: () => fixture.discoverer.calls == 1, reason: 'the burst did not sync');
      await quiet();

      expect(fixture.discoverer.calls, 1);
      expect(fixture.events, ['reload', 'changed']);
      expect(fixture.changes.revision, 1);
    });

    test('a quiet generation publishes nothing', () async {
      final fixture = build();
      fixture.discoverer.applied = 0;
      final paged = pagedSource();

      fixture.bridge.onStoreChanged(paged);
      await settle(done: () => fixture.discoverer.calls == 1, reason: 'the event did not sync');
      await quiet();

      expect(fixture.events, isEmpty);
      expect(fixture.changes.revision, 0);
    });

    test('a failed sync is swallowed, not published', () async {
      final fixture = build();
      fixture.discoverer.error = StateError('platform reply lost');
      final paged = pagedSource();

      fixture.bridge.onStoreChanged(paged);
      await settle(done: () => fixture.discoverer.calls == 1, reason: 'the event did not sync');
      await quiet();

      expect(fixture.events, isEmpty);
    });

    test('an import owns discovery while it runs', () async {
      final fixture = build(importStatus: _FakeImportStatus()..importing = true);
      final paged = pagedSource();

      fixture.bridge.onStoreChanged(paged);
      await quiet();

      expect(fixture.discoverer.calls, 0);
    });

    test('the browser is left alone while the database is filled', () async {
      final fixture = build(phase: _FakePhase()..browsing = true);
      final paged = pagedSource();

      fixture.bridge.onStoreChanged(paged);
      await quiet();

      expect(fixture.discoverer.calls, 0);
    });

    test('a change during a media operation waits for it to settle', () async {
      final fixture = build();
      fixture.discoverer.applied = 1;
      final paged = pagedSource()..pauseMonitoring();

      fixture.bridge.onStoreChanged(paged);
      await quiet();
      expect(fixture.discoverer.calls, 0);

      // The operation ended: the pending change is still owed.
      paged.resumeMonitoring();
      await settle(done: () => fixture.discoverer.calls == 1, reason: 'the deferred change never ran');
      expect(fixture.changes.revision, 1);
    });

    test('a change arriving mid-run lands in the next pass', () async {
      final fixture = build();
      fixture.discoverer
        ..applied = 1
        ..gate = Completer<void>();
      final paged = pagedSource();

      fixture.bridge.onStoreChanged(paged);
      await settle(done: () => fixture.discoverer.calls == 1, reason: 'the first change did not start');

      fixture.bridge.onStoreChanged(paged);
      await quiet();
      expect(fixture.discoverer.calls, 1);

      fixture.discoverer.gate!.complete();
      await settle(done: () => fixture.discoverer.calls == 2, reason: 'the queued change never ran');
      expect(fixture.changes.revision, greaterThanOrEqualTo(1));
    });
  });
}

class _FakeSummaries extends Fake implements FilterSummaryProvider;

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
