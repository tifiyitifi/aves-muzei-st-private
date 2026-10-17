import 'package:aves/geo/states.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/dynamic_album.dart';
import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/container/tag_group.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/date.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/missing.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/model/filters/rating.dart';
import 'package:aves/model/filters/recent.dart';
import 'package:aves/model/filters/type.dart';
import 'package:aves/model/filters/weekday.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
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

/// SQL mirror of `AvesEntry.bestDate`: the catalogued date, else the source
/// date, else the modification date — each one only when it is neither `0` nor
/// `-1`, which `dateTimeFromMillis` treats as "unknown".
///
/// NULL when the entry has no usable date; [bestDateExpression] adds the epoch
/// fallback the ordering uses.
const String bestDateIfSetExpression = 'COALESCE(NULLIF(NULLIF(dt.dateMillis, 0), -1), NULLIF(NULLIF(e.sourceDateTakenMillis, 0), -1), NULLIF(NULLIF(e.dateModifiedMillis, 0), -1))';

/// [bestDateIfSetExpression] with `0` for an absent date.
///
/// This is the single ordering/aggregate/grouping key, and matches
/// `AvesEntrySort.compareByDate`, which also substitutes the epoch: an entry
/// whose catalogued date is unknown falls back to its source or modification
/// date instead of sorting as if it were from 1970.
const String bestDateExpression = 'COALESCE($bestDateIfSetExpression, 0)';

/// [bestDateIfSetExpression] in whole seconds, for `strftime` calendar fields.
const String _bestDateSeconds = '$bestDateIfSetExpression / 1000';

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
    case TypeFilter():
      return _typeFragment(filter);
    case DateFilter():
      return _dateFragment(filter);
    case WeekDayFilter(weekday: final weekday):
      return _weekDayFragment(weekday);
    case RecentlyAddedFilter():
      return _recentlyAddedFragment();
    case MissingFilter():
      return _missingFragment(filter);
    case PathFilter(path: final path):
      return _pathFragment(path);
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

/// `MetadataTable.flags` bits, mirroring `CatalogMetadata`'s flag layout.
///
/// The layout is owned by `CatalogMetadata`; these copies let the compiler test
/// a flag without loading a row, and
/// `test/features/collection_paging/collection_filter_sql_test.dart` derives
/// every bit from `CatalogMetadata.toMap()` so the two cannot drift.
const int _flagAnimated = 1 << 0;
const int _flagGeotiff = 1 << 2;
const int _flag360 = 1 << 3;
const int _flagMotionPhoto = 1 << 5;
const int _flagHdr = 1 << 6;
const int _flagSlowMotion = 1 << 7;

WindowFragment _flagFragment(int mask) => (
      sql: '(COALESCE(m.flags, 0) & $mask) != 0',
      variables: const [],
      requires: const {WindowTable.metadata},
    );

/// `AvesEntry.mimeType` (catalogued mime, else source mime) starts with
/// [prefix].
///
/// Case-sensitive on purpose: the `MimeTypes` prefix tests are `startsWith`,
/// which SQLite's `LIKE` would make case-insensitive.
String _mimeStartsWith(String prefix) => "substr(COALESCE(m.mimeType, e.sourceMimeType), 1, ${prefix.length}) = '$prefix'";

WindowFragment? _typeFragment(TypeFilter filter) {
  // The persisted `itemType` values are private to `TypeFilter`; compare against
  // its public instances so the fork never spells them out.
  final itemType = filter.itemType;
  if (itemType == TypeFilter.animated.itemType) return _flagFragment(_flagAnimated);
  if (itemType == TypeFilter.geotiff.itemType) return _flagFragment(_flagGeotiff);
  if (itemType == TypeFilter.hdr.itemType) return _flagFragment(_flagHdr);
  if (itemType == TypeFilter.motionPhoto.itemType) return _flagFragment(_flagMotionPhoto);
  if (itemType == TypeFilter.panorama.itemType) return _mimeAndFlag('image', _flag360);
  if (itemType == TypeFilter.slowMotion.itemType) return _mimeAndFlag('video', _flagSlowMotion);
  if (itemType == TypeFilter.sphericalVideo.itemType) return _mimeAndFlag('video', _flag360);
  if (itemType == TypeFilter.raw.itemType) {
    // `MimeTypes.rawImages.contains(mimeType)`, exact case.
    final placeholders = MimeTypes.rawImages.map((_) => '?').join(',');
    return (
      sql: 'COALESCE(m.mimeType, e.sourceMimeType) IN ($placeholders)',
      variables: [for (final mime in MimeTypes.rawImages) Variable(mime)],
      requires: const {WindowTable.metadata},
    );
  }
  return null;
}

WindowFragment _mimeAndFlag(String prefix, int mask) {
  final flag = _flagFragment(mask);
  return (sql: '(${_mimeStartsWith(prefix)} AND ${flag.sql})', variables: flag.variables, requires: flag.requires);
}

WindowFragment? _missingFragment(MissingFilter filter) {
  final metadataType = filter.metadataType;
  if (metadataType == MissingFilter.date.metadataType) {
    // The *catalogued* date, not `bestDate`: `(catalogMetadata?.dateMillis ?? 0) == 0`.
    return (sql: 'COALESCE(m.dateMillis, 0) = 0', variables: const [], requires: const {WindowTable.metadata});
  }
  if (metadataType == MissingFilter.title.metadataType) {
    return (sql: "COALESCE(m.xmpTitle, '') = ''", variables: const [], requires: const {WindowTable.metadata});
  }
  if (metadataType == MissingFilter.fineAddress.metadataType) {
    // `hasGps && !hasFineAddress`: has a coordinate but neither a place nor a
    // full country name (the two conditions are two-valued, so COALESCE is only
    // for symmetry with the rest of the compiler).
    const placeExpr = "COALESCE(NULLIF(a.locality, ''), a.adminArea)";
    const fineAddress = "(($placeExpr IS NOT NULL AND $placeExpr != '') OR LENGTH(COALESCE(a.countryName, '')) > 3)";
    return (
      sql: '((COALESCE(m.latitude, 0) != 0 OR COALESCE(m.longitude, 0) != 0) AND COALESCE($fineAddress, 0) = 0)',
      variables: const [],
      requires: const {WindowTable.metadata, WindowTable.address},
    );
  }
  return null;
}

WindowFragment? _dateFragment(DateFilter filter) {
  // Only the Gregorian calendar maps to SQLite's date functions; the hijri and
  // persian ops convert through their own tables.
  if (filter.calendar != ACalendar.gregorian) return null;
  // `DateFilter` captures `date ?? now` at construction; re-reading `now` here
  // can only differ across midnight, and the legacy in-memory list is rebuilt on
  // the same lifecycle events.
  final date = filter.date ?? DateTime.now();
  const year = "CAST(strftime('%Y', $_bestDateSeconds, 'unixepoch', 'localtime') AS INTEGER)";
  const month = "CAST(strftime('%m', $_bestDateSeconds, 'unixepoch', 'localtime') AS INTEGER)";
  const day = "CAST(strftime('%d', $_bestDateSeconds, 'unixepoch', 'localtime') AS INTEGER)";
  // `DateFilter` tests `entry.bestDate`, which is null for entries without any
  // usable date: those match no date at all.
  final conditions = <String>['$bestDateIfSetExpression IS NOT NULL'];
  final variables = <Variable>[];
  void match(String expr, int value) {
    conditions.add('$expr = ?');
    variables.add(Variable(value));
  }

  switch (filter.level) {
    case DateLevel.y:
      match(year, date.year);
    case DateLevel.ym:
      match(year, date.year);
      match(month, date.month);
    case DateLevel.ymd:
      match(year, date.year);
      match(month, date.month);
      match(day, date.day);
    case DateLevel.md:
      // Any year.
      match(month, date.month);
      match(day, date.day);
    case DateLevel.m:
      match(month, date.month);
    case DateLevel.d:
      match(day, date.day);
  }
  return (sql: '(${conditions.join(' AND ')})', variables: variables, requires: const {WindowTable.dateTaken});
}

WindowFragment? _weekDayFragment(int weekday) {
  if (weekday < 1 || weekday > 7) return null;
  // `DateTime.weekday` is 1=Monday..7=Sunday while SQLite's `%w` is
  // 0=Sunday..6=Saturday.
  const weekDay = "CAST(strftime('%w', $_bestDateSeconds, 'unixepoch', 'localtime') AS INTEGER)";
  return (
    sql: '($bestDateIfSetExpression IS NOT NULL AND (((($weekDay + 6) % 7) + 1)) = ?)',
    variables: [Variable(weekday)],
    requires: const {WindowTable.dateTaken},
  );
}

WindowFragment _recentlyAddedFragment() => (
      // `(nowSecs - (dateAddedSecs ?? 0)) < 24h`; the odd-looking first clause
      // mirrors that an absent or zero date added is never "recent".
      sql: '(COALESCE(e.dateAddedSecs, 0) != 0 AND ? - e.dateAddedSecs < 86400)',
      variables: [Variable(RecentlyAddedFilter.nowSecs)],
      requires: const {},
    );

WindowFragment? _pathFragment(String normalizedPath) {
  // `PathFilter.path` is normalised with a trailing separator; the test is
  // `directory == root || directory is a descendant`, matched case-sensitively
  // (`LIKE` would fold case, `startsWith` does not).
  final separator = pContext.separator;
  final root = normalizedPath.endsWith(separator) ? normalizedPath.substring(0, normalizedPath.length - 1) : normalizedPath;
  final childPrefix = '$root$separator';
  return (
    sql: '(e.directory = ? OR substr(e.directory, 1, ?) = ?)',
    variables: [Variable(root), Variable(childPrefix.length), Variable(childPrefix)],
    requires: const {},
  );
}

/// Fragment excluding video entries: the `MimeFilter.video` complement the
/// slideshow uses when it skips videos.
///
/// Expressed through the same compiler, so the slideshow's skip can never
/// disagree with a reversed video filter chip.
WindowFragment excludeVideoFragment() => filterTestFragment(MimeFilter(MimeTypes.anyVideo, reversed: true))!;

/// Escapes the LIKE metacharacters in a literal pattern.
String escapeLike(String value) => value.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
