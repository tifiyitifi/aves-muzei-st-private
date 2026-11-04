import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/summary/paged_filter_summaries.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/vaults/vaults.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// One [PagedFilterSummaries] per source, owned by the library rather than by a
/// page.
///
/// The summaries answer for the library: album lists, counts, tags, locations.
/// They used to be created and dropped by the collection lens, which meant any
/// top-level page reached from the collection (albums, tags, places are pushed
/// with `pushAndRemoveUntil`, so the collection is disposed) found the source
/// without a provider and fell back to the legacy in-memory counts — zero for a
/// paged library, where nothing is materialized.
///
/// Keeping them per source makes the provider outlive any single page: a lens
/// attaches it on entry, a legacy view detaches it from the source (that path
/// materializes entries and must not consult the database), and the cached
/// aggregates survive across navigation.
final Map<CollectionSource, PagedFilterSummaries> _summaries = {};

PagedFilterSummaries pagedSummariesFor(CollectionSource source) => _summaries.putIfAbsent(
  source,
  () => PagedFilterSummaries(
    source: source,
    hiddenFilters: () => settings.hiddenFilters,
    lockedVaultDirs: () => vaults.vaultDirectories.where(vaults.isLocked).toSet(),
  ),
);

/// Makes [source] answer filter questions from the database.
void attachPagedSummaries(CollectionSource source) {
  source.summaries = pagedSummariesFor(source);
}

/// Reloads every live provider.
///
/// For writes that bypass the collection lens (the copy-first editor imports the files it staged),
/// so the album list and counts reflect them without waiting for the next resolve. Failures are
/// logged rather than thrown: the next resolve rebuilds the summaries anyway.
Future<void> reloadPagedSummaries() async {
  if (_summaries.isEmpty) return;
  await Future.wait(
    _summaries.values.map(
      (summaries) => summaries.reload().catchError((Object error, StackTrace stack) {
        _log.w('paged summary reload failed', error, stack);
      }),
    ),
  );
}

/// Drops the provider from [source] for a legacy view.
///
/// The cached instance stays in the registry (invalidated, so a later paged
/// view reloads it) instead of being thrown away: navigating between the
/// collection and a filter page must not rebuild every aggregate.
void detachPagedSummaries(CollectionSource source) {
  source.summaries = null;
  _summaries[source]?.invalidate();
}

/// Forgets a source's provider, for tests and for a disposed source.
void forgetPagedSummaries(CollectionSource source) {
  _summaries.remove(source)?.dispose();
}
