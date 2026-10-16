import 'package:aves/features/drift_db/filter_summary/hidden_exclusion.dart';
import 'package:aves/geo/states.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/dynamic_album.dart';
import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/container/tag_group.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/rating.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:drift/drift.dart';

/// Tables a window fragment reads besides `entry` (alias `e`).
///
/// Fragments declare their needs so the query builder joins only what the
/// predicate and the ordering actually touch: a whole-library count stays a
/// single-table scan.
enum WindowTable { dateTaken, metadata, address }

/// One AND-ed SQL fragment over the standard window aliases
/// (`e` entry, `dt` dateTaken, `m` metadata, `a` address).
typedef WindowFragment = ({String sql, List<Variable> variables, Set<WindowTable> requires});

/// Database-backed predicate of a collection view: the conjunction of the
/// filter atoms that translate to SQL without loss, plus the trash scope.
///
/// A collection view intersects its filters (see `CollectionLens`), so the
/// predicate ANDs one fragment per filter. Anything the SQL layer cannot
/// express (reversed filters, queries, bursts, ...) makes
/// [predicateForFilters] return null, and the caller keeps the legacy path.
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

/// Translates a collection view's [filters] (plus the user's hidden filters and
/// locked vaults) into a [CollectionWindowPredicate], or null when any filter
/// needs the legacy in-memory path.
///
/// Supported atoms: stored albums, album/tag groups, tags, dynamic albums
/// (unwrapped), locations (country/state/place), mime types, ratings,
/// favourites, and the `AND`/`OR` containers; the whole set intersects with
/// `AND`. Hidden filters ride along as the same SQL negation the summary store
/// uses, so an entry can never be both shown and hidden.
///
/// Reversed filters are intentionally unsupported: in SQL a negation would need
/// an `IS NULL` escape hatch per atom, and the legacy path already filters them
/// with full fidelity in memory.
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
    final fragment = _compileFilter(filter);
    if (fragment == null) return null;
    conjunction.add(fragment);
  }

  // Never silently ignore a hidden filter: an uncompilable one keeps the
  // legacy path, exactly as it did before hidden filters were paged.
  if (hidden.isNotEmpty && !isSummaryExclusionComplete(hidden)) return null;

  final exclusion = buildSummaryExclusion(hidden: hidden, lockedVaultDirs: lockedVaultDirs);
  if (exclusion.sql.isNotEmpty) {
    // The exclusion's fragments reference entry, metadata and address columns;
    // declaring both optional joins is conservative but always correct.
    conjunction.add((sql: exclusion.sql, variables: exclusion.variables, requires: const {WindowTable.metadata, WindowTable.address}));
  }

  return CollectionWindowPredicate(conjunction: conjunction, trashedOnly: trashedOnly);
}

WindowFragment? _compileFilter(CollectionFilter filter) {
  if (filter.reversed) return null;
  switch (filter) {
    case StoredAlbumFilter(album: final album):
      // `AvesEntry.directory == album`, matching the maintained `directory`
      // column (the same key the album section headers group by).
      return (sql: 'e.directory = ?', variables: [Variable(album)], requires: const {});
    case DynamicAlbumFilter(filter: final inner):
      // A dynamic album is an alias when its inner filter is simple and a
      // combination when it is a container; recursing covers both.
      return _compileFilter(inner);
    case AlbumGroupFilter(filter: final inner) || TagGroupFilter(filter: final inner):
      return _compileFilter(inner);
    case SetOrFilter():
      return _compileContainer(filter.innerFilters, isOr: true);
    case SetAndFilter():
      return _compileContainer(filter.innerFilters, isOr: false);
    case TagFilter(tag: final tag):
      return _tagFragment(tag);
    case LocationFilter():
      return _locationFragment(filter);
    case MimeFilter(mime: final mime):
      return _mimeFragment(mime);
    case RatingFilter(rating: final rating, op: final op):
      return _ratingFragment(rating, op);
    case FavouriteFilter():
      return (sql: 'EXISTS (SELECT 1 FROM favourites f WHERE f.id = e.id)', variables: const [], requires: const {});
    default:
      return null;
  }
}

WindowFragment? _compileContainer(Set<CollectionFilter> members, {required bool isOr}) {
  final fragments = <WindowFragment>[];
  for (final member in members) {
    final fragment = _compileFilter(member);
    if (fragment == null) return null;
    fragments.add(fragment);
  }
  if (fragments.isEmpty) {
    // Empty `OR` matches nothing, empty `AND` matches everything (mirrors
    // `SetOrFilter`/`SetAndFilter`'s in-memory predicates).
    return (sql: isOr ? '0 = 1' : '1 = 1', variables: const [], requires: const {});
  }
  return (
    sql: fragments.map((f) => '(${f.sql})').join(isOr ? ' OR ' : ' AND '),
    variables: [for (final f in fragments) ...f.variables],
    requires: {for (final f in fragments) ...f.requires},
  );
}

WindowFragment? _tagFragment(String tag) {
  const requires = {WindowTable.metadata};
  if (tag.isEmpty) {
    // `entry.tags.isEmpty`: no metadata row, or no non-empty `;`-segment.
    return (sql: "(m.id IS NULL OR COALESCE(m.xmpSubjects, '') = '')", variables: const [], requires: requires);
  }
  // `;`-wrapped membership so a tag never leaks into a longer one; LIKE
  // metacharacters in the tag itself are escaped, as in `hidden_exclusion`.
  return (
    sql: "(';' || COALESCE(m.xmpSubjects, '') || ';') LIKE ? ESCAPE '\\'",
    variables: [Variable('%;${_escapeLike(tag)};%')],
    requires: requires,
  );
}

WindowFragment? _locationFragment(LocationFilter filter) {
  if (filter.place.isEmpty) {
    // Unlocated: `!entry.hasGps`, the same coordinate test as `hidden_exclusion`.
    return (sql: '(COALESCE(m.latitude, 0) = 0 AND COALESCE(m.longitude, 0) = 0)', variables: const [], requires: const {WindowTable.metadata});
  }
  const requires = {WindowTable.address};
  switch (filter.level) {
    case .country:
      final code = filter.code;
      if (code == null) return null;
      return (sql: 'a.countryCode = ?', variables: [Variable(code)], requires: requires);
    case .state:
      final code = filter.code;
      if (code == null) return null;
      // `entry.addressDetails.stateCode` derives from `(countryCode, adminArea)`
      // through `GeoStates`; both sides are constrained as in `hidden_exclusion`.
      final names = <String>{};
      for (final kv in GeoStates.stateCodeByName.entries) {
        if (kv.value == code) names.add(kv.key);
      }
      if (names.isEmpty) return null;
      final namePlaceholders = List.filled(names.length, '?').join(',');
      final countryPlaceholders = List.filled(GeoStates.stateCodesByCountryCode.length, '?').join(',');
      return (
        sql: '(a.adminArea IN ($namePlaceholders) AND a.countryCode IN ($countryPlaceholders))',
        variables: [for (final name in names) Variable(name), for (final country in GeoStates.stateCodesByCountryCode.keys) Variable(country)],
        requires: requires,
      );
    case .place:
      // Same `locality ?? adminArea` fallback as `AddressDetails.place`.
      return (sql: "COALESCE(NULLIF(a.locality, ''), a.adminArea) = ?", variables: [Variable(filter.place)], requires: requires);
  }
}

WindowFragment? _mimeFragment(String mime) {
  const requires = {WindowTable.metadata};
  // `AvesEntry.mimeType = catalogued mimeType ?? sourceMimeType`, lowercased
  // comparison mirrors `MimeFilter`'s `lowMime`.
  const expr = 'LOWER(COALESCE(m.mimeType, e.sourceMimeType))';
  final low = mime.toLowerCase();
  if (low.endsWith('/*')) {
    final prefix = low.substring(0, low.length - 2);
    return (sql: "$expr LIKE ? ESCAPE '\\'", variables: [Variable('${_escapeLike(prefix)}%')], requires: requires);
  }
  return (sql: '$expr = ?', variables: [Variable(low)], requires: requires);
}

WindowFragment? _ratingFragment(int rating, String op) {
  const requires = {WindowTable.metadata};
  // `AvesEntry.rating = catalogued rating ?? 0`.
  const expr = 'COALESCE(m.rating, 0)';
  final sql = switch (op) {
    RatingFilter.opOrLower => '($expr <= ? AND $expr > 0)',
    RatingFilter.opOrGreater => '$expr >= ?',
    RatingFilter.opEqual => '$expr = ?',
    _ => null,
  };
  if (sql == null) return null;
  return (sql: sql, variables: [Variable(rating)], requires: requires);
}

/// Escapes the LIKE metacharacters in a literal pattern.
String _escapeLike(String value) => value.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
