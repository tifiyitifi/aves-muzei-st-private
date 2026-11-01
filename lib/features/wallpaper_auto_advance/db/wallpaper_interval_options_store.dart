import 'dart:convert';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/wallpaper_auto_advance/data/default_intervals.dart';
import 'package:aves/features/wallpaper_auto_advance/log.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_interval_catalog.dart';

/// Persists the shared option list in `AppMeta`.
///
/// The stored value distinguishes the built-ins currently present from the
/// user's own options, so Reset can clear both and 「Add default intervals」 can
/// restore only the built-ins. No schema change: this is bookkeeping, not data
/// the wallpaper engine reads.
class WallpaperIntervalOptionsStore {
  /// AppMeta key of the shared option list.
  static const keyOptions = 'wallpaper.autoAdvanceIntervals';

  final AppDatabase db;

  /// Loads the bundled list. Injectable so tests never read assets.
  final Future<WallpaperIntervalDefaults> Function() bundledLoader;

  new(this.db, {this.bundledLoader = loadWallpaperIntervalDefaults});

  /// The stored catalog, or null when the key is absent or unreadable.
  ///
  /// An unreadable value is treated as absent on purpose: reseeding the bundled
  /// list is a safe recovery, while keeping a truncated list would hide every
  /// option. A stored `{"defaults":[],"customs":[]}` is a real, intentional
  /// Reset state and is returned as-is.
  Future<WallpaperIntervalCatalog?> read() async {
    final values = await AppMetaStore(db).read({keyOptions});
    final raw = values[keyOptions];
    if (raw == null) return null;
    final parsed = _decode(raw);
    if (parsed == null) {
      wallpaperAutoAdvanceLog.w('discarding an unreadable interval option list');
      return null;
    }
    final bundled = await bundledLoader();
    return WallpaperIntervalCatalog(
      defaultInterval: bundled.defaultInterval,
      shippedDefaults: bundled.intervals,
      defaults: parsed.$1,
      customs: parsed.$2,
    );
  }

  Future<void> write(WallpaperIntervalCatalog catalog) => AppMetaStore(db).write({
        keyOptions: jsonEncode({
          'defaults': [for (final value in catalog.defaults) value.seconds],
          'customs': [for (final value in catalog.customs) value.seconds],
        }),
      });

  /// Reads the stored list, seeding the bundled one on first run.
  ///
  /// Only a missing (or unreadable) key seeds; an empty list is preserved so
  /// Reset stays cleared across restarts until the user asks for the defaults
  /// back.
  Future<WallpaperIntervalCatalog> loadOrSeed() async {
    final stored = await read();
    if (stored != null) return stored;
    final seeded = WallpaperIntervalCatalog.seeded(await bundledLoader());
    await write(seeded);
    return seeded;
  }

  (List<WallpaperAdvanceInterval>, List<WallpaperAdvanceInterval>)? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final rawDefaults = decoded['defaults'];
      final rawCustoms = decoded['customs'];
      if (rawDefaults is! List || rawCustoms is! List) return null;
      return (_parseList(rawDefaults), _parseList(rawCustoms));
    } catch (_) {
      return null;
    }
  }

  /// Tolerant like the bundled parser: a corrupt entry is skipped rather than
  /// invalidating the whole list.
  static List<WallpaperAdvanceInterval> _parseList(List<Object?> raw) => sorted([for (final entry in raw) ?_parseStored(entry)]);

  /// `0` is valid (off); a corrupt entry is skipped. Unlike user input, a stored
  /// value is never clamped: it is either one we can read or noise.
  static WallpaperAdvanceInterval? _parseStored(Object? value) {
    final seconds = value is num && value == value.roundToDouble() ? value.toInt() : null;
    if (seconds == null || seconds < 0 || seconds > WallpaperAdvanceInterval.maxSeconds) return null;
    if (seconds == 0) return WallpaperAdvanceInterval.off;
    if (seconds < WallpaperAdvanceInterval.minSeconds) return null;
    return WallpaperAdvanceInterval(seconds);
  }
}
