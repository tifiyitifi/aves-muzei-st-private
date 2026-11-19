import 'dart:async';

import 'package:aves/features/collection_paging/sync/paged_discoverer.dart';
import 'package:test/fake.dart';

/// Stands in for the generation-gated discoverer in the sync paths.
///
/// [gate] holds a run open so a test can observe what happens while one is in
/// flight; [error] makes the run fail the way a platform call does.
class FakePagedDiscoverer extends Fake implements PagedDiscoverer {
  int calls = 0;
  int applied = 0;
  Completer<void>? gate;
  Object? error;

  /// How many sweeps ran, and how many rows the last one reported removing.
  int sweepCalls = 0;
  int swept = 0;

  @override
  Future<int> syncIfChanged() async {
    calls++;
    final gate = this.gate;
    if (gate != null) await gate.future;
    final error = this.error;
    if (error != null) throw error;
    return applied;
  }

  @override
  Future<int> reconcileObsoleteMediaStoreRows({required Set<String> mountedVolumePaths}) async {
    sweepCalls++;
    return swept;
  }
}
