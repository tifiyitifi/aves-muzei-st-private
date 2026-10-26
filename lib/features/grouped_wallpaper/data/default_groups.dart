import 'dart:convert';

import 'package:aves/features/visible_range/data/default_presets.dart' show StandardPathResolver;
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:flutter/services.dart';

/// A built-in wallpaper group as declared in `assets/wallpaper_groups.json`.
///
/// Defaults live in the asset, not in code: the bundled set stays reviewable as
/// data, and a future bundle can add a group without touching the controller.
class WallpaperGroupDefinition {
  final String id;

  /// ARB key of the group name; built-in names are always localized.
  final String nameKey;
  final bool enabled;
  final bool current;

  /// Base filters of the group's visible range.
  final Set<CollectionFilter> filters;

  const new({
    required this.id,
    required this.nameKey,
    this.enabled = true,
    this.current = false,
    this.filters = const {},
  });
}

/// A base range that matches **no** entry.
///
/// Wallpaper groups guard private material, so every failure must lean towards
/// showing nothing instead of everything: a group whose standard path cannot be
/// resolved is seeded with this filter rather than left unrestricted. An empty
/// OR is exactly "nothing" in both paths — the in-memory predicate ORs over no
/// member, and SQL compiles it to `0 = 1` — and it round-trips through the
/// filter JSON codec like any other filter.
CollectionFilter wallpaperDenyAllFilter() => SetOrFilter(const {});

/// Parses the bundled group document.
///
/// Malformed entries are skipped: one unknown filter type introduced by a future
/// build must not remove every default group. A **path** that cannot be resolved
/// is different — it never skips the group, it closes it (see
/// [wallpaperDenyAllFilter]).
List<WallpaperGroupDefinition> parseWallpaperGroupBundle(
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
  final groups = decoded['groups'];
  if (groups is! List) return const [];

  final resolveStandardPath = standardPath ?? _defaultStandardPath;
  final result = <WallpaperGroupDefinition>[];
  for (final entry in groups) {
    if (entry is! Map) continue;
    final id = entry['id'];
    final nameKey = entry['nameKey'];
    if (id is! String || id.isEmpty || nameKey is! String || nameKey.isEmpty) continue;

    final filters = <CollectionFilter>{};
    var closed = false;
    for (final raw in entry['filters'] as List? ?? const []) {
      if (raw is! Map) continue;
      if (raw['type'] == PathFilter.type && raw['standard'] is String) {
        final path = resolveStandardPath(raw['standard'] as String);
        if (path == null || path.isEmpty) {
          closed = true;
          continue;
        }
        filters.add(PathFilter(path, reversed: raw['reversed'] == true));
        continue;
      }
      final filter = CollectionFilter.fromJson(raw);
      if (filter != null) filters.add(filter);
    }

    result.add(
      WallpaperGroupDefinition(
        id: id,
        nameKey: nameKey,
        enabled: entry['enabled'] != false,
        current: entry['current'] == true,
        // A default that names a folder we cannot resolve must not fall back to
        // 「everything」: a privacy feature fails closed, not open.
        filters: closed ? {wallpaperDenyAllFilter()} : filters,
      ),
    );
  }
  return result;
}

/// Loads the bundled group defaults shipped in assets.
Future<List<WallpaperGroupDefinition>> loadWallpaperGroupDefinitions({StandardPathResolver? standardPath}) async {
  final source = await rootBundle.loadString('assets/wallpaper_groups.json');
  return parseWallpaperGroupBundle(source, standardPath: standardPath);
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
