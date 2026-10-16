import 'package:aves/geo/states.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:drift/drift.dart';

/// SQL fragment excluding entries hidden by user filters or locked vaults.
///
/// Only the filter types expressible in SQL are compiled: stored albums (plus
/// locked vault directories) by directory, tags by `xmpSubjects`, locations
/// by address columns. Anything else (reversed filters, groups, dynamic
/// albums, queries, ratings, ...) is skipped and the summary stays
/// approximate for those entries — hidden filters are rare, and the legacy
/// in-memory path keeps full fidelity for small libraries.
///
/// Null-preserving: entries without an address or directory never match a
/// hidden album/tag/location test in memory, so the SQL guards every `NOT IN`
/// with an `IS NULL` escape hatch.
typedef SummaryExclusion = ({String sql, List<Variable> variables});

SummaryExclusion buildSummaryExclusion({
  required Set<CollectionFilter> hidden,
  required Set<String> lockedVaultDirs,
}) {
  final conditions = <String>[];
  final variables = <Variable>[];

  void addInList(String column, Set<String> values) {
    if (values.isEmpty) return;
    final placeholders = values.map((_) => '?').join(',');
    conditions.add('($column IS NULL OR $column NOT IN ($placeholders))');
    for (final value in values) {
      variables.add(Variable(value));
    }
  }

  final hiddenDirs = <String>{...lockedVaultDirs};
  final hiddenTags = <String>{};
  var hideUntagged = false;
  final hiddenCountryCodes = <String>{};
  final hiddenStateCodes = <String>{};
  final hiddenPlaces = <String>{};
  var hideUnlocated = false;

  for (final filter in hidden) {
    if (filter.reversed) continue;
    switch (filter) {
      case StoredAlbumFilter(album: final album):
        hiddenDirs.add(album);
      case TagFilter(tag: final tag):
        if (tag.isEmpty) {
          hideUntagged = true;
        } else {
          hiddenTags.add(tag);
        }
      case LocationFilter(level: final level, code: final code, place: final place):
        switch (level) {
          case .country:
            if (code != null) hiddenCountryCodes.add(code);
          case .state:
            if (code != null) hiddenStateCodes.add(code);
          case .place:
            if (place.isEmpty) {
              hideUnlocated = true;
            } else {
              hiddenPlaces.add(place);
            }
        }
      default:
        continue;
    }
  }

  addInList('e.directory', hiddenDirs);
  addInList('a.countryCode', hiddenCountryCodes);

  if (hiddenTags.isNotEmpty) {
    // `;`-wrapped match so `a` never leaks into `ab`; LIKE metacharacters in
    // the tag itself are escaped, mirroring the directory-prefix escaping in
    // `EntryStore._windowWhere`.
    for (final tag in hiddenTags) {
      final escaped = tag.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
      conditions.add("(m.id IS NULL OR (';' || COALESCE(m.xmpSubjects, '') || ';') NOT LIKE ? ESCAPE '\\')");
      variables.add(Variable('%;$escaped;%'));
    }
  }
  if (hideUntagged) {
    conditions.add("(m.id IS NOT NULL AND COALESCE(m.xmpSubjects, '') != '')");
  }

  if (hiddenStateCodes.isNotEmpty) {
    // Invert the Dart `name -> code` map to the admin-area names producing a
    // hidden code. Legacy only assigns a state inside countries with a states
    // mapping, so both sides are constrained.
    final names = <String>{};
    for (final kv in GeoStates.stateCodeByName.entries) {
      if (hiddenStateCodes.contains(kv.value)) names.add(kv.key);
    }
    if (names.isNotEmpty) {
      final namePlaceholders = names.map((_) => '?').join(',');
      final countryPlaceholders = GeoStates.stateCodesByCountryCode.keys.map((_) => '?').join(',');
      conditions.add('(a.adminArea IS NULL OR NOT (a.adminArea IN ($namePlaceholders) AND a.countryCode IN ($countryPlaceholders)))');
      for (final name in names) {
        variables.add(Variable(name));
      }
      for (final country in GeoStates.stateCodesByCountryCode.keys) {
        variables.add(Variable(country));
      }
    }
  }
  if (hiddenPlaces.isNotEmpty) {
    // Same `locality ?? adminArea` fallback as `AddressDetails.place`.
    const placeExpr = "COALESCE(NULLIF(a.locality, ''), a.adminArea)";
    final placeholders = hiddenPlaces.map((_) => '?').join(',');
    conditions.add('($placeExpr IS NULL OR $placeExpr NOT IN ($placeholders))');
    for (final place in hiddenPlaces) {
      variables.add(Variable(place));
    }
  }
  if (hideUnlocated) {
    // Same definition as `AvesEntry.hasGps`; entries without catalogued
    // coordinates (including rows with no metadata at all) are dropped.
    conditions.add('(COALESCE(m.latitude, 0) != 0 OR COALESCE(m.longitude, 0) != 0)');
  }

  return (sql: conditions.join(' AND '), variables: variables);
}

/// `true` when the exclusion carries no conditions.
extension SummaryExclusionX on SummaryExclusion {
  bool get isEmpty => sql.isEmpty;
}
