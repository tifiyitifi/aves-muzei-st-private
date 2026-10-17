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
import 'package:aves/ref/mime_types.dart';
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

/// Translates a filter into SQL equivalent to `filter.test(entry)`.
///
/// The contract the whole window predicate relies on:
///   * the positive fragment evaluates to `1` exactly when `positiveTest(entry)`
///     is true, and to `0` — or NULL, where comparing a NULL column makes the
///     Dart test false — otherwise;
///   * therefore a *reversed* filter is `COALESCE(<positive>, 0) = 0` ("the
///     positive test is not true"). A bare `NOT` would drop the rows where a
///     comparison is NULL, but Dart's `!test` keeps them: an entry with no
///     directory is *not* in `/comics`, so a reversed album filter must keep it.
///
/// Returns null when the filter has no SQL translation; callers then keep the
/// legacy in-memory path instead of showing a different set of entries.
WindowFragment? filterTestFragment(CollectionFilter filter) {
  final positive = _positiveFragment(filter);
  if (positive == null) return null;
  return filter.reversed ? _negated(positive) : positive;
}

/// The filter's positive test, ignoring its own [CollectionFilter.reversed].
///
/// Containers recurse through [filterTestFragment], so a member's own reversal
/// is honoured: `SetOrFilter`/`SetAndFilter`/groups all define their positive
/// test as `member.test`, not `member.positiveTest`.
WindowFragment? _positiveFragment(CollectionFilter filter) {
  switch (filter) {
    case StoredAlbumFilter(album: final album):
      // `AvesEntry.directory == album`, matching the maintained `directory`
      // column (the same key the album section headers group by).
      return (sql: 'e.directory = ?', variables: [Variable(album)], requires: const {});
    case DynamicAlbumFilter(filter: final inner):
      // A dynamic album is an alias when its inner filter is simple and a
      // combination when it is a container; `positiveTest` delegates either way.
      return filterTestFragment(inner);
    case AlbumGroupFilter(filter: final inner) || TagGroupFilter(filter: final inner):
      // `GroupBaseFilter.positiveTest` delegates to the member `SetOrFilter`.
      return filterTestFragment(inner);
    case SetOrFilter():
      return _container(filter.innerFilters, isOr: true);
    case SetAndFilter():
      return _container(filter.innerFilters, isOr: false);
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

/// `NOT <positive filter test>`, NULL-safe.
///
/// `COALESCE(P, 0) = 0` reads "[P] is false or unknown", which is exactly the
/// set of entries where the Dart test is false.
WindowFragment _negated(WindowFragment positive) => (
      sql: 'COALESCE((${positive.sql}), 0) = 0',
      variables: positive.variables,
      requires: positive.requires,
    );

WindowFragment? _container(Set<CollectionFilter> members, {required bool isOr}) {
  final fragments = <WindowFragment>[];
  for (final member in members) {
    final fragment = filterTestFragment(member);
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
  // metacharacters in the tag itself are escaped.
  return (
    sql: "(';' || COALESCE(m.xmpSubjects, '') || ';') LIKE ? ESCAPE '\\'",
    variables: [Variable('%;${escapeLike(tag)};%')],
    requires: requires,
  );
}

WindowFragment? _locationFragment(LocationFilter filter) {
  if (filter.place.isEmpty) {
    // Unlocated: `!entry.hasGps`.
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
      // through `GeoStates`; both sides are constrained.
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
    return (sql: "$expr LIKE ? ESCAPE '\\'", variables: [Variable('${escapeLike(prefix)}%')], requires: requires);
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

/// Fragment excluding video entries: the `MimeFilter.video` complement the
/// slideshow uses when it skips videos.
///
/// Expressed through the same compiler, so the slideshow's skip can never
/// disagree with a reversed video filter chip.
WindowFragment excludeVideoFragment() => filterTestFragment(MimeFilter(MimeTypes.anyVideo, reversed: true))!;

/// Escapes the LIKE metacharacters in a literal pattern.
String escapeLike(String value) => value.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
