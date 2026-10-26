import 'dart:convert';

import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:flutter/services.dart';

/// Which section a built-in candidate belongs to.
///
/// Base candidates are exclusive (picking one replaces the base); restrictions
/// are AND-ed and supplements OR-ed. The asset declares the section so the page
/// can show every default in place instead of inventing rules for it.
enum VisibleRangePresetKind {
  base,
  restriction,
  supplement;

  static VisibleRangePresetKind parse(Object? value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return base;
  }
}

/// A built-in candidate as declared in `assets/visible_range_presets.json`.
///
/// A base entry normally carries one filter. `builtin.cameraRecent6h` is kept on
/// purpose with two: it shows that a mutually exclusive base range may itself
/// combine conditions (folder + time span), instead of only offering single ones.
class VisibleRangePresetDefinition {
  final String id;

  /// ARB key; built-in names are always localized, never hardcoded.
  final String nameKey;
  final VisibleRangePresetKind kind;
  final Set<CollectionFilter> filters;

  const new({
    required this.id,
    required this.nameKey,
    this.kind = VisibleRangePresetKind.base,
    this.filters = const {},
  });
}

/// Resolves a device-specific standard directory (`dcim`, `pictures`, ...).
///
/// The asset cannot contain an absolute path: the primary storage differs
/// between devices and users. A null result means the path is not known yet, and
/// the candidate is skipped rather than saved with a wrong path.
typedef StandardPathResolver = String? Function(String standard);

/// Parses the bundled preset document.
///
/// Malformed entries are skipped rather than aborting the whole bundle: a single
/// unknown filter type added by a future build must not remove every default.
List<VisibleRangePresetDefinition> parseVisibleRangePresetBundle(
  String source, {
  StandardPathResolver? standardPath,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map) return const [];
  final presets = decoded['presets'];
  if (presets is! List) return const [];

  final resolveStandardPath = standardPath ?? _defaultStandardPath;
  final result = <VisibleRangePresetDefinition>[];
  for (final entry in presets) {
    if (entry is! Map) continue;
    final id = entry['id'];
    final nameKey = entry['nameKey'];
    if (id is! String || id.isEmpty || nameKey is! String || nameKey.isEmpty) continue;

    final filters = <CollectionFilter>{};
    for (final raw in entry['filters'] as List? ?? const []) {
      if (raw is! Map) continue;
      if (raw['type'] == PathFilter.type && raw['standard'] is String) {
        final path = resolveStandardPath(raw['standard'] as String);
        if (path == null || path.isEmpty) continue;
        filters.add(PathFilter(path, reversed: raw['reversed'] == true));
        continue;
      }
      final filter = CollectionFilter.fromJson(raw);
      if (filter != null) filters.add(filter);
    }
    // A default without a usable filter would render as an empty tile and, when
    // selected, match everything; skip it instead.
    if (filters.isEmpty) continue;

    result.add(
      VisibleRangePresetDefinition(
        id: id,
        nameKey: nameKey,
        kind: VisibleRangePresetKind.parse(entry['kind']),
        filters: filters,
      ),
    );
  }
  return result;
}

/// Loads the built-in preset bundle shipped in assets.
Future<List<VisibleRangePresetDefinition>> loadVisibleRangePresetDefinitions({StandardPathResolver? standardPath}) async {
  final source = await rootBundle.loadString('assets/visible_range_presets.json');
  return parseVisibleRangePresetBundle(source, standardPath: standardPath);
}

String? _defaultStandardPath(String standard) {
  try {
    return switch (standard) {
      'dcim' => androidFileUtils.dcimPath,
      'pictures' => androidFileUtils.picturesPath,
      'movies' => androidFileUtils.moviesPath,
      'download' => androidFileUtils.downloadPath,
      _ => null,
    };
  } catch (_) {
    // Storage volumes are not ready yet (early startup or a test without
    // services); the caller retries once they are.
    return null;
  }
}
