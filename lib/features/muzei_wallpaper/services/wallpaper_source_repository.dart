import 'dart:io';
import 'dart:math';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/muzei_wallpaper/log.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_single_artwork.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_resolution.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:path/path.dart' as p;

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

  /// The wallpaper root, needed to resolve a single artwork's copy.
  final Directory? stateRoot;

  /// The copy the current scope points at, if any.
  ///
  /// A slot stores only the entry id, so validating a single-artwork slot after
  /// a restart has to translate that id back to the copy. No other scope can
  /// produce that id, and the snapshot is tiny.
  final WallpaperSingleArtwork? Function()? singleArtwork;

  new({
    this.database,
    Random? random,
    this.stateRoot,
    this.singleArtwork,
  }) : _random = random ?? Random();

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

  /// How many random samples to try before accepting a recently shown artwork.
  ///
  /// The exclusion set is the queued artworks plus the recent list (bounded by
  /// `WallpaperState.maxRecent`), so a few tries find a fresh one in any library
  /// larger than that; a tiny library can exhaust it and must repeat.
  static const int maxRandomAttempts = 12;

  /// How many new entries to scan past an unusable one in a single pick.
  static const int maxNewScan = 8;

  /// Picks the artwork to show next.
  ///
  /// [cursor] is the in-order position remembered by the controller; it wraps
  /// around the source and is ignored by the other orderings. [attempt] is used
  /// by the bake retry loop: it shifts the position, so a decode failure never
  /// retries the same photo.
  ///
  /// [newestEntryId] is the highest entry id shown so far (Muzei's
  /// `maxLoadedArtworkId`) and [excludeEntryIds] the queued artworks plus the
  /// recently shown ones, so the random ordering does not repeat itself.
  Future<WallpaperSourcePick> pick(
    WallpaperSourceScope scope, {
    required WallpaperOrdering ordering,
    required int cursor,
    int attempt = 0,
    int newestEntryId = 0,
    Set<int> excludeEntryIds = const {},
  }) async {
    final resolution = await resolve(scope);
    if (!resolution.isReady) return WallpaperSourcePick.fromResolution(resolution);

    final total = resolution.total;
    if (scope.kind == WallpaperSourceKind.single) {
      // One artwork: ordering and exclusion are meaningless, and the single
      // scope's predicate covers the whole library, which must never leak in.
      final entry = await pickAt(scope, total: total, offset: 0);
      if (entry == null) return _emptyPick(scope, total: total, offset: 0);
      return WallpaperSourcePick(
        status: WallpaperSourceStatus.ready,
        entry: entry,
        total: total,
        offset: 0,
      );
    }

    if (ordering == WallpaperOrdering.newThenRandom) {
      final fresh = await _pickNew(
        scope,
        newestEntryId: newestEntryId,
        attempt: attempt,
        excludeEntryIds: excludeEntryIds,
      );
      if (fresh != null) {
        // The position within the collection is unknown without another query,
        // and only the in-order cursor consumes it; new picks do not need it.
        return WallpaperSourcePick(
          status: WallpaperSourceStatus.ready,
          entry: fresh,
          total: total,
          offset: 0,
        );
      }
      // No new photos left: Muzei falls through to the random strategy.
    }

    if (ordering == WallpaperOrdering.inOrder) {
      final offset = _normalize(cursor + attempt, total);
      final entry = await pickAt(scope, total: total, offset: offset);
      if (entry == null) return _emptyPick(scope, total: total, offset: offset);
      return WallpaperSourcePick(
        status: WallpaperSourceStatus.ready,
        entry: entry,
        total: total,
        offset: offset,
      );
    }

    final randomPick = await _pickRandom(scope, total: total, attempt: attempt, excludeEntryIds: excludeEntryIds);
    if (randomPick == null) return _emptyPick(scope, total: total, offset: -1);
    return WallpaperSourcePick(
      status: WallpaperSourceStatus.ready,
      entry: randomPick.entry,
      total: total,
      offset: randomPick.offset,
    );
  }

  WallpaperSourcePick _emptyPick(WallpaperSourceScope scope, {required int total, required int offset}) {
    // The count and the window disagree, which can only happen when the
    // library changed in between. The caller retries on the next advance.
    wallpaperLog.w('source window is empty scope=${scope.kind.name} total=$total offset=$offset');
    return WallpaperSourcePick(
      status: scope.kind == WallpaperSourceKind.single ? WallpaperSourceStatus.missing : WallpaperSourceStatus.empty,
      total: total,
      offset: offset,
    );
  }

  /// One artwork added after [newestEntryId], in id order.
  ///
  /// Entry ids are MediaStore ids, which grow with insertion, so walking forward
  /// from the last one shown is Muzei's `_id > maxLoadedArtworkId` step. [attempt]
  /// steps past retried bakes; [maxNewScan] tolerates a few unusable rows.
  Future<AvesEntry?> _pickNew(
    WallpaperSourceScope scope, {
    required int newestEntryId,
    required int attempt,
    required Set<int> excludeEntryIds,
  }) async {
    if (newestEntryId <= 0) return null;
    final predicate = _predicateFor(scope);
    if (predicate == null) return null;
    final db = _db;
    await db.init();
    final rows = await db.loadWalkWindow(
      predicate: predicate,
      afterId: newestEntryId,
      limit: attempt + 1 + maxNewScan,
    );
    var position = 0;
    for (final entry in rows) {
      if (!_isUsable(entry) || excludeEntryIds.contains(entry.id)) continue;
      if (position++ < attempt) continue;
      return entry;
    }
    return null;
  }

  /// A random artwork, avoiding the current one and the recently shown ones.
  ///
  /// Rejection sampling, like Muzei's shuffled sequence: the exclusion set is
  /// small, so a handful of tries is enough. A library barely larger than the
  /// set can exhaust the tries, and repeating is better than a blank wallpaper.
  Future<({AvesEntry entry, int offset})?> _pickRandom(
    WallpaperSourceScope scope, {
    required int total,
    required int attempt,
    required Set<int> excludeEntryIds,
  }) async {
    for (var i = 0; i < maxRandomAttempts; i++) {
      final offset = _normalize(_random.nextInt(total) + attempt + i, total);
      final entry = await pickAt(scope, total: total, offset: offset);
      if (entry == null || excludeEntryIds.contains(entry.id)) continue;
      return (entry: entry, offset: offset);
    }
    final offset = _normalize(_random.nextInt(total) + attempt, total);
    final entry = await pickAt(scope, total: total, offset: offset);
    return entry == null ? null : (entry: entry, offset: offset);
  }

  /// The id of the newest artwork in [scope], used to seed the "new" marker.
  ///
  /// Muzei starts at zero and walks its whole feed in order; an Aves library can
  /// hold tens of thousands of photos, so "new" means "added after the wallpaper
  /// was set up" instead of "not shown yet", which would take years to exhaust.
  Future<int> newestEntryId(WallpaperSourceScope scope) async {
    if (scope.kind == WallpaperSourceKind.single) return scope.singleArtwork?.entryId ?? scope.singleEntryId ?? 0;
    final predicate = _predicateFor(scope);
    if (predicate == null) return 0;
    final db = _db;
    await db.init();
    final rows = await db.loadEntryWindow(
      predicate: predicate,
      sort: SortFactor.date,
      reverse: false,
      limit: 1,
      offset: 0,
    );
    return rows.isEmpty ? 0 : rows.first.id;
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

  /// A single scope resolves to the copy the app made, when there is one.
  ///
  /// Scopes saved before copies existed (or whose copy is gone) fall back to the
  /// original entry through the media library.
  Future<AvesEntry?> _loadSingle(WallpaperSourceScope scope) async {
    final artwork = scope.singleArtwork;
    if (artwork != null) {
      final copy = await singleArtworkEntry(artwork);
      if (copy != null) return copy;
    }
    return entryById(scope.singleEntryId ?? 0);
  }

  /// Loads one current artwork by id, applying the same usability test as a
  /// pick.
  ///
  /// Hidden filters are deliberately not applied: an explicit single choice
  /// overrides them, while trash and locked vaults still make an entry
  /// unusable. The controller uses it to validate the persisted slot after a
  /// restart and to reopen the displayed artwork in the viewer.
  ///
  /// The private copy wins when it carries [id]: the wallpaper keeps using the
  /// bytes it copied even after the original is gone.
  Future<AvesEntry?> entryById(int id) async {
    if (id <= 0) return null;
    final artwork = singleArtwork?.call();
    if (artwork != null && artwork.entryId == id) {
      final copy = await singleArtworkEntry(artwork);
      if (copy != null) return copy;
    }
    return libraryEntryById(id);
  }

  /// Loads the library entry [id], never the private copy.
  ///
  /// The viewer is a place to edit and delete: handing it the read-only copy
  /// would hide those actions even while the original is still in the library.
  Future<AvesEntry?> libraryEntryById(int id) async {
    if (id <= 0) return null;
    final db = _db;
    await db.init();
    final entries = await db.loadEntriesById({id});
    if (entries.isEmpty) return null;
    final entry = entries.first;
    return _isUsable(entry) ? entry : null;
  }

  /// Builds an entry for the bytes the app copied, or null when no longer usable.
  ///
  /// The copy is a plain file under the wallpaper root. Its metadata comes from
  /// the snapshot instead of the library: the original may be gone, and EXIF
  /// alone cannot restore the user's rotation and flip.
  Future<AvesEntry?> singleArtworkEntry(WallpaperSingleArtwork artwork) async {
    final root = stateRoot;
    if (root == null) return null;
    final file = File(p.join(root.path, artwork.relativePath));
    try {
      if (!await file.exists()) return null;
    } on FileSystemException {
      return null;
    }
    final entry = AvesEntry(
      id: artwork.entryId,
      uri: file.uri.toString(),
      path: file.path,
      contentId: null,
      pageId: null,
      sourceMimeType: artwork.mimeType,
      width: artwork.width,
      height: artwork.height,
      sourceRotationDegrees: artwork.rotationDegrees,
      sizeBytes: artwork.sizeBytes,
      sourceTitle: artwork.title,
      dateAddedSecs: null,
      dateModifiedMillis: null,
      sourceDateTakenMillis: null,
      durationMillis: null,
      trashed: false,
      origin: EntryOrigins.file,
    );
    entry.catalogMetadata = CatalogMetadata(
      id: artwork.entryId,
      mimeType: artwork.mimeType,
      isAnimated: artwork.isAnimated,
      isFlipped: artwork.isFlipped,
      rotationDegrees: artwork.rotationDegrees,
      // The file is always named `single.*`, so the copy path cannot supply the
      // display title the original had; the snapshot keeps it.
      xmpTitle: artwork.title,
    );
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
