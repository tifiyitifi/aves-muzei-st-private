import 'package:aves/features/wallpaper_auto_advance/data/default_intervals.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The process-wide option list for wallpaper auto-advance intervals.
///
/// The list itself is shared by the grouped wallpaper and the Muzei wallpaper,
/// while each group and Muzei keep their own selected value elsewhere. Built-ins
/// can be cleared and restored as a block; only [customs] can be deleted
/// individually.
@immutable
class WallpaperIntervalCatalog with Equatable {
  /// Reset target, read from the bundled JSON.
  final WallpaperAdvanceInterval defaultInterval;

  /// The shipped built-ins, so 「Add default intervals」 knows what to restore
  /// even after the list was cleared.
  final List<WallpaperAdvanceInterval> shippedDefaults;

  /// Built-in options currently present. Seeded from the bundle, then only
  /// changed by Reset (empty) and 「Add default intervals」.
  final List<WallpaperAdvanceInterval> defaults;

  /// User-added options; the only ones that can be deleted one by one.
  final List<WallpaperAdvanceInterval> customs;

  const new({
    required this.defaultInterval,
    required this.shippedDefaults,
    required this.defaults,
    required this.customs,
  });

  /// First run: the bundled list is in use and nothing is custom yet.
  factory seeded(WallpaperIntervalDefaults bundled) => WallpaperIntervalCatalog(
        defaultInterval: bundled.defaultInterval,
        shippedDefaults: bundled.intervals,
        defaults: bundled.intervals,
        customs: const [],
      );

  /// Every selectable option, deduplicated and ascending.
  List<WallpaperAdvanceInterval> get options => sorted([...defaults, ...customs]);

  /// Built-ins the bundle declares but the current list lost.
  List<WallpaperAdvanceInterval> get missingDefaults => [
        for (final value in shippedDefaults)
          if (!defaults.contains(value)) value,
      ];

  bool isCustom(WallpaperAdvanceInterval value) => customs.contains(value);

  bool contains(WallpaperAdvanceInterval value) => defaults.contains(value) || customs.contains(value);

  WallpaperIntervalCatalog copyWith({
    WallpaperAdvanceInterval? defaultInterval,
    List<WallpaperAdvanceInterval>? shippedDefaults,
    List<WallpaperAdvanceInterval>? defaults,
    List<WallpaperAdvanceInterval>? customs,
  }) =>
      WallpaperIntervalCatalog(
        defaultInterval: defaultInterval ?? this.defaultInterval,
        shippedDefaults: shippedDefaults ?? this.shippedDefaults,
        defaults: defaults ?? this.defaults,
        customs: customs ?? this.customs,
      );

  @override
  List<Object?> get props => [defaultInterval, shippedDefaults, defaults, customs];
}

/// Deduplicates by seconds and sorts ascending, so the page order never depends
/// on the order values were added.
List<WallpaperAdvanceInterval> sorted(Iterable<WallpaperAdvanceInterval> values) {
  final bySeconds = <int, WallpaperAdvanceInterval>{
    for (final value in values) value.seconds: value,
  };
  final seconds = bySeconds.keys.toList()..sort();
  return [for (final value in seconds) bySeconds[value]!];
}
