import 'package:aves/features/batch_ops/model/batch_paths.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/filters.dart';

/// Whether a collection view is exactly the batch results folder.
///
/// The banner offers to replace originals, so it must not appear in a
/// multi-filter view or in a broader album that merely contains the folder: the
/// rows it acts on are what the app recorded, and those only line up with what
/// is on screen in the folder's own view.
///
/// The predicate lives here rather than in the grid so the scope has one owner
/// and a fixture can call it with a filter set.
bool isBatchResultsView(Set<CollectionFilter> visibleFilters) {
  if (visibleFilters.length != 1) return false;
  final filter = visibleFilters.first;
  return filter is StoredAlbumFilter && isBatchResultsPath(filter.album);
}
