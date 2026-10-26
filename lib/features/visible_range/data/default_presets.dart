import 'dart:convert';

import 'package:aves/model/filters/filters.dart';
import 'package:flutter/services.dart';

/// A built-in base-range preset as declared in `assets/visible_range_presets.json`.
class VisibleRangePresetDefinition {
  final String id;

  /// ARB key; built-in names are always localized, never hardcoded.
  final String nameKey;
  final Set<CollectionFilter> filters;

  const new({
    required this.id,
    required this.nameKey,
    this.filters = const {},
  });
}

/// Parses the bundled preset document.
///
/// Malformed entries are skipped rather than aborting the whole bundle: a single
/// unknown filter type added by a future build must not remove every default.
List<VisibleRangePresetDefinition> parseVisibleRangePresetBundle(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map) return const [];
  final presets = decoded['presets'];
  if (presets is! List) return const [];

  final result = <VisibleRangePresetDefinition>[];
  for (final entry in presets) {
    if (entry is! Map) continue;
    final id = entry['id'];
    final nameKey = entry['nameKey'];
    if (id is! String || id.isEmpty || nameKey is! String || nameKey.isEmpty) continue;
    final filters = (entry['filters'] as List? ?? const []).map(CollectionFilter.fromJson).nonNulls.toSet();
    result.add(VisibleRangePresetDefinition(id: id, nameKey: nameKey, filters: filters));
  }
  return result;
}

/// Loads the built-in preset bundle shipped in assets.
Future<List<VisibleRangePresetDefinition>> loadVisibleRangePresetDefinitions() async {
  final source = await rootBundle.loadString('assets/visible_range_presets.json');
  return parseVisibleRangePresetBundle(source);
}
