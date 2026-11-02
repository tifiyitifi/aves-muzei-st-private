import 'dart:convert';

import 'package:aves/features/grouped_wallpaper/model/wallpaper_condition_pool.dart';
import 'package:aves/features/visible_range/data/default_presets.dart' show StandardPathResolver;
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:flutter/services.dart';

/// A restriction every bundled group starts with.
///
/// The shipped orientation conditions are demonstrations: they make an empty
/// group easy to produce while testing, and the page lists them as ordinary
/// conditions the user can unmark or delete. Home starts on `notPortrait` and
/// lock on `portrait`, so the two surfaces stay visibly different once the
/// split is turned on.
class WallpaperGroupRuleDefinition {
  final String key;

  /// ARB key of the rule label; built-in labels are always localized.
  final String nameKey;
  final Set<CollectionFilter> filters;

  /// The surfaces that use the condition, as a [WallpaperConditionSurfaces] mask.
  final int surfaces;

  const new({
    required this.key,
    required this.nameKey,
    this.filters = const {},
    this.surfaces = 0,
  });

  /// The stored rule id for [groupId].
  ///
  /// The `.default.` segment is what the prune pass uses to tell a bundled
  /// condition from the gallery's old materialized catalogue.
  String idFor(String groupId) => '$groupId.rule.default.$key';
}

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

  /// Restrictions seeded into the group's condition pool.
  ///
  /// The bundle declares them once at the top level and every group shares the
  /// list: a group is a starting point, and the four orientation conditions are
  /// the same demonstration in all of them.
  final List<WallpaperGroupRuleDefinition> rules;

  const new({
    required this.id,
    required this.nameKey,
    this.enabled = true,
    this.current = false,
    this.filters = const {},
    this.rules = const [],
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

  // Shared by every group: the bundle declares the demonstration conditions
  // once, and each group's pool gets the same four rows.
  final defaultRules = _parseRuleList(decoded['restrictions']);
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
        rules: defaultRules,
      ),
    );
  }
  return result;
}

/// Parses the bundle's shared restriction list.
///
/// A malformed rule is skipped like a malformed group: one bad entry must not
/// remove the demonstration conditions from every group.
List<WallpaperGroupRuleDefinition> _parseRuleList(Object? raw) {
  if (raw is! List) return const [];
  final rules = <WallpaperGroupRuleDefinition>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final key = entry['key'];
    final nameKey = entry['nameKey'];
    if (key is! String || key.isEmpty || nameKey is! String || nameKey.isEmpty) continue;
    final filters = <CollectionFilter>{};
    for (final rawFilter in entry['filters'] as List? ?? const []) {
      if (rawFilter is! Map) continue;
      final filter = CollectionFilter.fromJson(rawFilter);
      if (filter != null) filters.add(filter);
    }
    if (filters.isEmpty) continue;
    var surfaces = 0;
    for (final surface in entry['surfaces'] as List? ?? const []) {
      switch (surface) {
        case 'home':
          surfaces |= WallpaperConditionSurfaces.home;
        case 'lock':
          surfaces |= WallpaperConditionSurfaces.lock;
      }
    }
    rules.add(WallpaperGroupRuleDefinition(key: key, nameKey: nameKey, filters: filters, surfaces: surfaces));
  }
  return rules;
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
