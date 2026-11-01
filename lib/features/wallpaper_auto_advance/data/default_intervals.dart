import 'dart:convert';

import 'package:aves/features/wallpaper_auto_advance/log.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The option list and reset target shipped in
/// `assets/wallpaper_intervals.json`.
///
/// Keeping the defaults in an asset means the list can change without touching
/// Dart, and the reset target is a product decision, not a constant in code.
@immutable
class WallpaperIntervalDefaults {
  final int version;

  /// The value Reset falls back to. `0` (off) by default.
  final WallpaperAdvanceInterval defaultInterval;

  /// Built-in options, always containing [WallpaperAdvanceInterval.off] and
  /// [defaultInterval].
  final List<WallpaperAdvanceInterval> intervals;

  const new({
    this.version = 0,
    this.defaultInterval = WallpaperAdvanceInterval.off,
    this.intervals = const [WallpaperAdvanceInterval.off],
  });
}

/// Parses the bundled document tolerantly, like the visible-range presets: one
/// bad entry must not cost the user the whole list.
WallpaperIntervalDefaults parseWallpaperIntervalDefaults(String source) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map) return const WallpaperIntervalDefaults();
    final version = _int(decoded['version']) ?? 0;
    final rawIntervals = decoded['intervals'];
    final seconds = <int>{
      for (final entry in rawIntervals is List ? rawIntervals : const []) ?_validSeconds(entry),
    };
    final defaultInterval = WallpaperAdvanceInterval.fromSeconds(decoded['defaultSeconds']);
    // Off must always be selectable, and Reset must land on a listed option.
    seconds
      ..add(0)
      ..add(defaultInterval.seconds);
    final sorted = seconds.toList()..sort();
    return WallpaperIntervalDefaults(
      version: version,
      defaultInterval: defaultInterval,
      intervals: [for (final value in sorted) WallpaperAdvanceInterval(value)],
    );
  } catch (error) {
    wallpaperAutoAdvanceLog.w('failed to parse the bundled interval defaults', error);
    return const WallpaperIntervalDefaults();
  }
}

/// Loads the bundled defaults once per process. A missing asset falls back to
/// 「off only」 so the pages stay usable.
Future<WallpaperIntervalDefaults> loadWallpaperIntervalDefaults() => _bundledFuture ??= _loadBundledDefaults();

Future<WallpaperIntervalDefaults>? _bundledFuture;

Future<WallpaperIntervalDefaults> _loadBundledDefaults() async {
  try {
    final source = await rootBundle.loadString('assets/wallpaper_intervals.json');
    return parseWallpaperIntervalDefaults(source);
  } catch (error, stack) {
    wallpaperAutoAdvanceLog.w('failed to read the bundled interval defaults', error, stack);
    return const WallpaperIntervalDefaults();
  }
}

int? _int(Object? value) => value is int ? value : (value is num && value == value.roundToDouble() ? value.toInt() : null);

int? _validSeconds(Object? value) {
  final seconds = _int(value);
  if (seconds == null) return null;
  if (seconds == 0) return 0;
  if (seconds < WallpaperAdvanceInterval.minSeconds || seconds > WallpaperAdvanceInterval.maxSeconds) return null;
  return seconds;
}
