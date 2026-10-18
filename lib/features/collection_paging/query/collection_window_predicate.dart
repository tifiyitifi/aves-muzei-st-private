import 'package:aves/features/collection_paging/query/collection_filter_sql.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/drift.dart';

export 'package:aves/features/collection_paging/query/collection_filter_sql.dart';

/// Database-backed predicate of a collection view: the conjunction of the
/// filter atoms that translate to SQL without loss, plus the trash scope.
///
/// A collection view intersects its filters (see `CollectionLens`), so the
/// predicate ANDs one fragment per filter. Anything the SQL layer cannot
/// express makes [predicateForFilters] return null, and the caller keeps the
/// legacy in-memory path.
class CollectionWindowPredicate {
  /// AND-ed fragments. Empty means the whole (trash-scoped) library.
  final List<WindowFragment> conjunction;

  /// Trash view: only trashed entries. Otherwise only live entries.
  final bool trashedOnly;

  const new({
    this.conjunction = const [],
    this.trashedOnly = false,
  });

  /// Union of the tables every fragment reads.
  Set<WindowTable> get requires => {for (final fragment in conjunction) ...fragment.requires};

  @override
  String toString() => '$runtimeType{trashedOnly=$trashedOnly, fragments=${conjunction.map((f) => f.sql).toList()}}';
}

/// SQL fragment excluding entries hidden by user filters or locked vaults.
typedef SummaryExclusion = ({String sql, List<Variable> variables, bool complete});

/// `true` when the exclusion carries no conditions.
extension SummaryExclusionX on SummaryExclusion {
  bool get isEmpty => sql.isEmpty;
}

/// Builds the exclusion of [hidden] filters plus [lockedVaultDirs].
///
/// Each hidden filter becomes the complement of its own compiled test, so this
/// shares one filter→SQL translation with the positive side (a hidden filter
/// can never disagree with the same filter used as a view) and honours
/// reversed hidden filters too.
///
/// [SummaryExclusion.complete] is false when a hidden filter has no SQL
/// translation: the generated SQL is then *approximate*, which the summary
/// store tolerates but the window predicate must not (it would show a hidden
/// entry), so the latter falls back to the legacy path.
SummaryExclusion buildSummaryExclusion({
  required Set<CollectionFilter> hidden,
  required Set<String> lockedVaultDirs,
}) {
  final conditions = <String>[];
  final variables = <Variable>[];
  var complete = true;

  if (lockedVaultDirs.isNotEmpty) {
    // Prefix test, not a directory equality: a vault's content is recognized by
    // `vaults.isVaultEntryUri` as everything *under* the vault directory, so
    // hiding the directory alone would leak a file that ended up nested in it.
    // The trailing separator keeps a sibling whose name starts with the same
    // prefix (a vault `a` and a vault `ab`) out of the test.
    final tests = <String>[];
    for (final dir in lockedVaultDirs) {
      final prefix = dir.endsWith(pContext.separator) ? dir : '$dir${pContext.separator}';
      // Entries with no directory are never inside a vault, so they are kept.
      tests.add('(e.directory = ? OR substr(e.directory, 1, ?) = ?)');
      variables
        ..add(Variable(dir))
        ..add(Variable(prefix.length))
        ..add(Variable(prefix));
    }
    conditions.add('(e.directory IS NULL OR NOT (${tests.join(' OR ')}))');
  }

  for (final filter in hidden) {
    final fragment = filterTestFragment(filter);
    if (fragment == null) {
      complete = false;
      continue;
    }
    // Hide the entries the filter matches: the complement of its test.
    conditions.add('COALESCE((${fragment.sql}), 0) = 0');
    variables.addAll(fragment.variables);
  }

  return (sql: conditions.join(' AND '), variables: variables, complete: complete);
}

/// Translates a collection view's [filters] (plus the user's hidden filters and
/// locked vaults) into a [CollectionWindowPredicate], or null when any filter
/// needs the legacy in-memory path.
///
/// Supported atoms: stored albums, album/tag groups, tags, dynamic albums
/// (unwrapped), locations (country/state/place), mime types, ratings,
/// favourites, path, type, missing, Gregorian dates/weekdays, recently-added,
/// aspect ratio, coordinates, the `AND`/`OR` containers, the `KEY<op>value` and
/// plain title forms of a query, and the reverse of every one of them; the whole
/// set intersects with `AND`. A `/regex/` query and a non-Gregorian calendar stay
/// on the legacy path.
CollectionWindowPredicate? predicateForFilters(
  Set<CollectionFilter> filters, {
  Set<CollectionFilter> hidden = const {},
  Set<String> lockedVaultDirs = const {},
}) {
  final conjunction = <WindowFragment>[];
  var trashedOnly = false;
  for (final filter in filters) {
    if (filter is TrashFilter) {
      trashedOnly = true;
      continue;
    }
    final fragment = filterTestFragment(filter);
    if (fragment == null) return null;
    conjunction.add(fragment);
  }

  final exclusion = buildSummaryExclusion(hidden: hidden, lockedVaultDirs: lockedVaultDirs);
  // Never silently ignore a hidden filter: an uncompilable one keeps the legacy
  // path, exactly as it did before hidden filters were paged.
  if (!exclusion.complete) return null;
  if (exclusion.sql.isNotEmpty) {
    // A hidden filter can be any supported atom, so every optional join is
    // declared; they are only touched when the user actually hid something.
    conjunction.add((
      sql: exclusion.sql,
      variables: exclusion.variables,
      requires: const {WindowTable.dateTaken, WindowTable.metadata, WindowTable.address},
    ));
  }

  return CollectionWindowPredicate(conjunction: conjunction, trashedOnly: trashedOnly);
}
