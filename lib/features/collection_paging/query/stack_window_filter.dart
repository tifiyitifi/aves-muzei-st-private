import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';

/// Hides every stack member whose tile lies inside [predicate]'s own scope.
///
/// `NOT IN` on the primary key: a member shows exactly when its tile is not in
/// this scope, so a filter that excludes the tile returns its members instead of
/// deleting them. The subquery reuses the predicate's fragments and joins, so the
/// scope is the same one the window resolves.
///
/// A view that counts tiles (the paged lens) and a sheet that previews how many
/// entries a condition matches must apply the same filter, or the count exceeds
/// what the grid shows.
CollectionWindowPredicate withStackFilter(CollectionWindowPredicate predicate) {
  final joins = [
    if (predicate.requires.contains(WindowTable.dateTaken)) 'LEFT JOIN dateTaken dt ON dt.id = e.id',
    if (predicate.requires.contains(WindowTable.metadata)) 'LEFT JOIN metadata m ON m.id = e.id',
    if (predicate.requires.contains(WindowTable.address)) 'LEFT JOIN address a ON a.id = e.id',
  ].join(' ');
  final conditions = <String>[
    predicate.trashedOnly ? 'e.trashed != 0' : 'e.trashed = 0',
    for (final fragment in predicate.conjunction) fragment.sql,
  ];
  return CollectionWindowPredicate(
    conjunction: [
      ...predicate.conjunction,
      (
        sql: '(e.stackTileId IS NULL OR e.stackTileId NOT IN (SELECT e.id FROM entry e ${joins.isEmpty ? '' : '$joins '}WHERE ${conditions.join(' AND ')}))',
        variables: [for (final fragment in predicate.conjunction) ...fragment.variables],
        requires: predicate.requires,
      ),
    ],
    trashedOnly: predicate.trashedOnly,
  );
}
