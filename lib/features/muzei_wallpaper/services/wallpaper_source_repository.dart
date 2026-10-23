import 'dart:math';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/muzei_wallpaper/log.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_resolution.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';

/// Resolves a [WallpaperSourceScope] to concrete entries in the Drift database.
///
/// Every call re-queries the database on purpose: the wallpaper must notice
/// deletions, newly imported photos, hidden filters and locked vaults between
/// two advances, exactly like a freshly opened collection view. The repository
/// owns that translation so the controller and the background worker never
/// build SQL predicates themselves.
class WallpaperSourceRepository {
  /// Injected in tests; production falls back to the app-wide [localMediaDb].
  final LocalMediaDb? database;

  /// Seeded in tests so random ordering stays reproducible.
  final Random _random;

  new({this.database, Random? random}) : _random = random ?? Random();

  LocalMediaDb get _db => database ?? localMediaDb;

  /// Whether the scope currently has anything to show, and how many.
  ///
  /// A single-entry scope is validated by loading it, because the entry may
  /// have been deleted, trashed or moved into a locked vault since it was
  /// chosen. A collection scope only needs its compiled predicate and count.
  Future<WallpaperSourceResolution> resolve(WallpaperSourceScope scope) => switch (scope.kind) {
    WallpaperSourceKind.single => _resolveSingle(scope),
    WallpaperSourceKind.myPhotos => _resolveCollection(scope),
  };

  /// Picks the artwork to show next.
  ///
  /// [cursor] is the in-order position remembered by the controller; it wraps
  /// around the source and is ignored by [WallpaperOrdering.random], which
  /// draws a new position from the repository's random source. [attempt] is
  /// used by the bake retry loop: it shifts the position by that many entries,
  /// so a decode failure never retries the same photo.
  Future<WallpaperSourcePick> pick(
    WallpaperSourceScope scope, {
    required WallpaperOrdering ordering,
    required int cursor,
    int attempt = 0,
  }) async {
    final resolution = await resolve(scope);
    if (!resolution.isReady) return WallpaperSourcePick.fromResolution(resolution);

    final total = resolution.total;
    final offset = switch (ordering) {
      WallpaperOrdering.inOrder => _normalize(cursor + attempt, total),
      WallpaperOrdering.random => _normalize(_random.nextInt(total) + attempt, total),
    };
    final entry = await pickAt(scope, total: total, offset: offset);
    if (entry == null) {
      // The count and the window disagree, which can only happen when the
      // library changed in between. The caller retries on the next advance.
      wallpaperLog.w('source window is empty scope=${scope.kind.name} total=$total offset=$offset');
      return WallpaperSourcePick(
        status: scope.kind == WallpaperSourceKind.single ? WallpaperSourceStatus.missing : WallpaperSourceStatus.empty,
        total: total,
        offset: offset,
      );
    }
    return WallpaperSourcePick(
      status: WallpaperSourceStatus.ready,
      entry: entry,
      total: total,
      offset: offset,
    );
  }

  /// Reads the entry at [offset] within a scope whose total is already known.
  ///
  /// Used by the bake retry loop, so it must not re-count the collection. The
  /// offset is normalized, and null means "nothing usable at that position".
  Future<AvesEntry?> pickAt(WallpaperSourceScope scope, {required int total, required int offset}) async {
    if (total <= 0) return null;
    final index = _normalize(offset, total);
    return switch (scope.kind) {
      WallpaperSourceKind.single => index == 0 ? _loadSingle(scope) : null,
      WallpaperSourceKind.myPhotos => _pickCollectionAt(scope, index),
    };
  }

  Future<WallpaperSourceResolution> _resolveSingle(WallpaperSourceScope scope) async {
    final entry = await _loadSingle(scope);
    return entry != null ? WallpaperSourceResolution.ready(1) : WallpaperSourceResolution.missing;
  }

  Future<WallpaperSourceResolution> _resolveCollection(WallpaperSourceScope scope) async {
    final predicate = _predicateFor(scope);
    if (predicate == null) {
      return WallpaperSourceResolution.unsupported('filters need the in-memory path');
    }
    final db = _db;
    await db.init();
    final total = await db.countEntries(predicate);
    return total > 0 ? WallpaperSourceResolution.ready(total) : WallpaperSourceResolution.empty;
  }

  Future<AvesEntry?> _pickCollectionAt(WallpaperSourceScope scope, int offset) async {
    final predicate = _predicateFor(scope);
    if (predicate == null) return null;
    final db = _db;
    await db.init();
    final rows = await db.loadEntryWindow(
      predicate: predicate,
      // The same ordering the collection views use, so an in-order walk
      // follows the library instead of an arbitrary database order.
      sort: SortFactor.date,
      reverse: false,
      limit: 1,
      offset: offset,
    );
    if (rows.isEmpty) return null;
    final entry = rows.first;
    // The predicate already enforces these; re-checking one row keeps the
    // wallpaper safe if the state changed between the count and the window.
    return _isUsable(entry) ? entry : null;
  }

  Future<AvesEntry?> _loadSingle(WallpaperSourceScope scope) => entryById(scope.singleEntryId ?? 0);

  /// Loads one current artwork by id, applying the same usability test as a
  /// pick.
  ///
  /// Hidden filters are deliberately not applied: an explicit single choice
  /// overrides them, while trash and locked vaults still make an entry
  /// unusable. The controller uses it to validate the persisted slot after a
  /// restart and to reopen the displayed artwork in the viewer.
  Future<AvesEntry?> entryById(int id) async {
    if (id <= 0) return null;
    final db = _db;
    await db.init();
    final entries = await db.loadEntriesById({id});
    if (entries.isEmpty) return null;
    final entry = entries.first;
    return _isUsable(entry) ? entry : null;
  }

  /// Builds the SQL predicate of a collection scope.
  ///
  /// [WallpaperSourceScope.queryFilters] always adds the image MIME filter, so
  /// a video scope can never leak a video into the wallpaper. Hidden filters
  /// and locked vaults are applied exactly like the browse views apply them.
  CollectionWindowPredicate? _predicateFor(WallpaperSourceScope scope) => predicateForFilters(
    scope.queryFilters,
    hidden: settings.hiddenFilters,
    lockedVaultDirs: _lockedVaultDirs(),
  );

  Set<String> _lockedVaultDirs() => vaults.vaultDirectories.where(vaults.isLocked).toSet();

  bool _isUsable(AvesEntry entry) => entry.isImage && !entry.trashed && !_isInLockedVault(entry);

  /// An entry nested under a locked vault is not a wallpaper candidate.
  ///
  /// The SQL predicate uses a prefix test for the same reason: a file that
  /// ended up in a vault subdirectory still belongs to the vault.
  bool _isInLockedVault(AvesEntry entry) {
    final dir = entry.directory;
    if (dir == null) return false;
    final separator = pContext.separator;
    for (final vaultDir in _lockedVaultDirs()) {
      if (dir == vaultDir) return true;
      final prefix = vaultDir.endsWith(separator) ? vaultDir : '$vaultDir$separator';
      if (dir.startsWith(prefix)) return true;
    }
    return false;
  }

  /// Wraps [value] into `[0, total)`, including negative cursors.
  static int _normalize(int value, int total) => ((value % total) + total) % total;
}
