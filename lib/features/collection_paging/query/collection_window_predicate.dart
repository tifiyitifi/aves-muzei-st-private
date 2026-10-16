import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/trash.dart';

/// Database-backed predicate of a collection view: the part of the filter set
/// that translates to SQL `WHERE` without loss.
///
/// Supported: no filters (whole library), a single non-reversed
/// [StoredAlbumFilter] (one album), and the trash view. Anything fancier
/// (tags, ratings, queries, favourites, locations, hidden filters, exclusions)
/// keeps the legacy in-memory path, which filters Dart-side with full fidelity.
class CollectionWindowPredicate {
  final int? origin;
  final String? directory;
  final bool excludeTrashed;

  /// Trash view: only trashed entries.
  final bool trashedOnly;

  const new({
    this.origin,
    this.directory,
    this.excludeTrashed = true,
    this.trashedOnly = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionWindowPredicate &&
          runtimeType == other.runtimeType &&
          origin == other.origin &&
          directory == other.directory &&
          excludeTrashed == other.excludeTrashed &&
          trashedOnly == other.trashedOnly);

  @override
  int get hashCode => Object.hash(origin, directory, excludeTrashed, trashedOnly);

  @override
  String toString() => '$runtimeType{origin=$origin, directory=$directory, excludeTrashed=$excludeTrashed, trashedOnly=$trashedOnly}';
}

/// Translates [filters] to a [CollectionWindowPredicate], or null when any
/// filter needs the legacy path.
CollectionWindowPredicate? predicateForFilters(Set<CollectionFilter> filters) {
  String? directory;
  var trashedOnly = false;
  for (final filter in filters) {
    if (filter is TrashFilter) {
      trashedOnly = true;
      continue;
    }
    final album = filter is StoredAlbumFilter ? filter : null;
    if (album == null || album.reversed) return null;
    if (directory != null) return null;
    directory = album.album;
  }
  return CollectionWindowPredicate(directory: directory, excludeTrashed: !trashedOnly, trashedOnly: trashedOnly);
}
