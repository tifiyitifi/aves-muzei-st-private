import 'package:aves/features/collection_paging/catalog/paged_catalog_worker.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/source/collection_source.dart';

const _log = AreaKeyLog('log.collection_paging');

/// The paged half of the background analysis service.
///
/// The legacy service path loads the whole library (`MediaStoreSource.init` over
/// the full scope) before analysing it, which on a collection too large to load
/// is the very OOM the paged engine exists to avoid. This runs the same
/// database-backed keyset sweep the in-app worker does instead, so such a
/// collection can still be catalogued while the app is in the background.
///
/// The source is used for state and events only: entries are materialized from
/// the database one chunk at a time, so no library is ever held here. Progress
/// flows through the source's own notifiers, which is what the service
/// notification reads.
class PagedAnalyzer {
  final CollectionSource source;

  PagedCatalogWorker? _worker;

  new({required this.source});

  bool get isRunning => _worker?.isRunning ?? false;

  /// Sweeps the whole backlog, resuming from the persisted cursor, until it
  /// finishes or [stop] is called.
  Future<void> run() async {
    _log.d('paged analyzer run');
    final worker = _worker = PagedCatalogWorker(source: source);
    await worker.run();
  }

  void stop() {
    _log.d('paged analyzer stop');
    _worker?.stop();
  }
}
