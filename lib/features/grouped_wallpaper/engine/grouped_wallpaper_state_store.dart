import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:path/path.dart' as p;

/// A baked frame read back from the cache.
///
/// The paths are relative to the state root, exactly like a slot's, so the
/// renderer cannot tell a cached frame from a freshly baked one.
class GroupedWallpaperFrame {
  final String photo;
  final String effectHome;
  final String effectLock;
  final int width;
  final int height;
  final double darkness;

  const new({
    required this.photo,
    this.effectHome = '',
    this.effectLock = '',
    this.width = 0,
    this.height = 0,
    this.darkness = .5,
  });
}

/// Owns the grouped wallpaper's on-disk directory.
///
/// Layout:
/// ```
/// <root>/state.json              # Dart-owned, read by the native renderer
/// <root>/runtime.json            # native-owned: the slot the renderer promoted to
/// <root>/lock_request.json       # native-owned: a lock tapped while the app slept
/// <root>/frames/<entryId>/<key>/ # baked photos, keyed by entry id and layout
/// <root>/slots/<id>/photo.png    # legacy frames written before the cache (v<6)
/// <root>/tmp/                    # atomic-write staging
/// ```
///
/// A frame lives under its entry id instead of its slot id so stepping back
/// through the usage history is a file reference, not a bake: the same photo at
/// the same layout is reused by any slot that shows it. [key] carries the surface
/// and the effects, so a changed layout or effect re-bakes instead of showing a
/// stale frame.
///
/// Writes go through `tmp/` and are renamed over the destination, so the native
/// renderer never observes a truncated JSON file or PNG. The root is separate
/// from Muzei's, so the two live-wallpaper features cannot read each other's
/// files.
class GroupedWallpaperStateStore {
  static const String stateFileName = 'state.json';
  static const String runtimeFileName = 'runtime.json';
  static const String lockRequestFileName = 'lock_request.json';
  static const String slotsDirName = 'slots';
  static const String slotPhotoFileName = 'photo.png';

  /// Baked effect images of a slot; absent when the effect is the identity.
  static const String slotEffectHomeFileName = 'home.png';
  static const String slotEffectLockFileName = 'lock.png';
  static const String tmpDirName = 'tmp';

  /// The frame cache root, and the metadata file of one cached frame.
  static const String framesDirName = 'frames';
  static const String frameMetaFileName = 'frame.json';

  final Directory root;

  new(this.root);

  /// The production location: `<app files>/grouped_wallpaper`.
  static GroupedWallpaperStateStore inAppFiles(Directory filesDir) => GroupedWallpaperStateStore(Directory(p.join(filesDir.path, 'grouped_wallpaper')));

  File get stateFile => File(p.join(root.path, stateFileName));

  File get runtimeFile => File(p.join(root.path, runtimeFileName));

  File get lockRequestFile => File(p.join(root.path, lockRequestFileName));

  /// The group a notification lock request names, or null when none is waiting.
  ///
  /// The request is written by the native side when the user taps the bar's lock
  /// while the app is not listening, so the tap is persisted before anything
  /// else can fail. A request older than [lockRequestMaxAge] is ignored: the bar
  /// stopped showing the lock long ago, and adopting it on a much later start
  /// would lock a group the user no longer asked for.
  Future<String?> readLockRequest({int? nowMillis}) async {
    if (!await lockRequestFile.exists()) return null;
    try {
      final raw = await lockRequestFile.readAsString();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final groupId = decoded['groupId'];
      if (groupId is! String || groupId.isEmpty) return null;
      final at = decoded['at'];
      final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
      if (at is num && now - at.toInt() > lockRequestMaxAge.inMilliseconds) {
        groupedWallpaperLog.i('ignoring a stale lock request at=${at.toInt()}');
        return null;
      }
      return groupId;
    } catch (error, stack) {
      groupedWallpaperLog.w('failed to read $lockRequestFileName', error, stack);
      return null;
    }
  }

  /// How long a lock request stays meaningful.
  ///
  /// The bar shows a pending lock for 30 seconds, so a request from far longer
  /// ago belongs to a tap the user has already seen fail.
  static const Duration lockRequestMaxAge = Duration(minutes: 10);

  /// Drops the request once the lock is persisted.
  Future<void> clearLockRequest() => _deleteQuietly(lockRequestFile);

  Directory get slotsDir => Directory(p.join(root.path, slotsDirName));

  Directory get framesDir => Directory(p.join(root.path, framesDirName));

  Directory get tmpDir => Directory(p.join(root.path, tmpDirName));

  /// Photo file of slot [id], named [name].
  File slotPhoto(int id, {String name = slotPhotoFileName}) => File(p.join(slotsDir.path, '$id', name));

  /// Directory of one cached frame.
  Directory frameDir(int entryId, String key) => Directory(p.join(framesDir.path, '$entryId', key));

  File frameFile(int entryId, String key, String name) => File(p.join(frameDir(entryId, key).path, name));

  /// Path of the cached [name] relative to the root, or `''` when it is absent.
  String framePath(int entryId, String key, String name) {
    if (entryId <= 0 || key.isEmpty) return '';
    return frameFile(entryId, key, name).existsSync() ? '$framesDirName/$entryId/$key/$name' : '';
  }

  /// The cached frame for [entryId] at [key], or null on a miss.
  ///
  /// [key] already carries the surface and the effects, so a hit is exactly "this
  /// photo at this layout": the caller can show it without baking.
  GroupedWallpaperFrame? cachedFrame(int entryId, String key) {
    if (entryId <= 0 || key.isEmpty) return null;
    final photo = framePath(entryId, key, slotPhotoFileName);
    if (photo.isEmpty) return null;
    final meta = _readFrameMeta(entryId, key);
    return GroupedWallpaperFrame(
      photo: photo,
      effectHome: framePath(entryId, key, slotEffectHomeFileName),
      effectLock: framePath(entryId, key, slotEffectLockFileName),
      width: meta.width,
      height: meta.height,
      darkness: meta.darkness,
    );
  }

  /// Writes one frame's photo and returns its path relative to the root.
  Future<String> writeFramePhoto(int entryId, String key, Uint8List bytes, {String name = slotPhotoFileName}) async {
    await ensureLayout();
    final target = frameFile(entryId, key, name);
    await target.parent.create(recursive: true);
    final tmp = File(p.join(tmpDir.path, 'frame.$entryId.$name.${DateTime.now().microsecondsSinceEpoch}.tmp'));
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await _replace(tmp, target);
      // POSIX separators: the native renderer resolves this against the root and
      // must not depend on the platform that wrote it.
      return '$framesDirName/$entryId/$key/$name';
    } catch (error, stack) {
      await _deleteQuietly(tmp);
      groupedWallpaperLog.e('failed to write the wallpaper frame of entry $entryId', error, stack);
      rethrow;
    }
  }

  /// Records what a frame looks like, for a later cache hit.
  Future<void> writeFrameMeta(int entryId, String key, {required int width, required int height, required double darkness, required String title, required String uri}) async {
    await ensureLayout();
    await frameDir(entryId, key).create(recursive: true);
    await _writeJson(
      frameFile(entryId, key, frameMetaFileName),
      {
        'width': width,
        'height': height,
        'darkness': darkness,
        'title': title,
        'uri': uri,
        'at': DateTime.now().millisecondsSinceEpoch,
      },
      frameMetaFileName,
    );
  }

  /// Drops cached frames the queue no longer needs, oldest first.
  ///
  /// [keep] holds the paths the current state references: they are the frames the
  /// renderer may step to next, so they are never evicted. [maxFrames] bounds the
  /// walk through the usage history, which is what keeps stepping back instant
  /// without letting the cache grow with the whole library.
  Future<void> pruneFrames({required Set<String> keep, required int maxFrames}) async {
    if (!await framesDir.exists()) return;
    final referenced = <String>{
      for (final path in keep)
        if (path.startsWith('$framesDirName/')) path.split('/').take(3).join('/'),
    };
    final candidates = <({Directory dir, int at})>[];
    try {
      await for (final entryDir in framesDir.list()) {
        if (entryDir is! Directory) continue;
        final entryName = p.basename(entryDir.path);
        await for (final keyDir in entryDir.list()) {
          if (keyDir is! Directory) continue;
          final relative = '$framesDirName/$entryName/${p.basename(keyDir.path)}';
          if (referenced.contains(relative)) continue;
          candidates.add((dir: keyDir, at: _frameUsedAt(keyDir)));
        }
      }
    } catch (error, stack) {
      groupedWallpaperLog.w('failed to list the wallpaper frame cache', error, stack);
      return;
    }
    final limit = maxFrames < referenced.length ? referenced.length : maxFrames;
    if (referenced.length + candidates.length <= limit) return;
    // Newest first, so the oldest are the ones dropped.
    candidates.sort((a, b) => b.at.compareTo(a.at));
    final drop = candidates.skip(limit - referenced.length);
    var dropped = 0;
    for (final candidate in drop) {
      try {
        await candidate.dir.delete(recursive: true);
        dropped++;
      } catch (error, stack) {
        groupedWallpaperLog.w('failed to delete the wallpaper frame ${candidate.dir.path}', error, stack);
      }
    }
    if (dropped > 0) groupedWallpaperLog.d('frames.prune dropped=$dropped kept=${referenced.length}');
  }

  /// Deletes every cached frame except [keep].
  Future<void> clearFrames({Set<String> keep = const {}}) async {
    if (!await framesDir.exists()) return;
    await pruneFrames(keep: keep, maxFrames: keep.length);
  }

  int _frameUsedAt(Directory dir) {
    try {
      final meta = File(p.join(dir.path, frameMetaFileName));
      if (meta.existsSync()) {
        final decoded = jsonDecode(meta.readAsStringSync());
        if (decoded is Map) {
          final at = decoded['at'];
          if (at is num) return at.toInt();
        }
      }
      return dir.statSync().modified.millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  ({int width, int height, double darkness}) _readFrameMeta(int entryId, String key) {
    try {
      final file = frameFile(entryId, key, frameMetaFileName);
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map) {
          return (
            width: decoded['width'] is num ? (decoded['width'] as num).toInt() : 0,
            height: decoded['height'] is num ? (decoded['height'] as num).toInt() : 0,
            darkness: decoded['darkness'] is num ? (decoded['darkness'] as num).toDouble().clamp(0.0, 1.0).toDouble() : .5,
          );
        }
      }
    } catch (_) {
      // A corrupt sidecar only loses the preview metadata, not the frame.
    }
    return (width: 0, height: 0, darkness: .5);
  }

  /// Photo file named by [slot], or null when it is not on disk.
  File? slotPhotoOf(GroupedWallpaperSlot slot) {
    if (slot.photo.isEmpty) return null;
    // Stored paths are always POSIX-style, so the state file the native renderer
    // reads is identical on every platform.
    final file = File(p.joinAll([root.path, ...slot.photo.split('/')]));
    return file.existsSync() ? file : null;
  }

  /// The effect photo of [slot] for a surface, falling back to the sharp photo
  /// when the effect is the identity or its file is gone.
  File? slotEffectPhotoOf(GroupedWallpaperSlot slot, {required bool lock}) {
    final photo = lock ? slot.effectLock : slot.effectHome;
    if (photo.isEmpty) return slotPhotoOf(slot);
    final file = File(p.joinAll([root.path, ...photo.split('/')]));
    return file.existsSync() ? file : slotPhotoOf(slot);
  }

  /// Whether the stored effect path exists, without falling back to the sharp
  /// photo: the queue is not ready when a baked effect was deleted.
  bool effectPhotoExists(String photo) {
    if (photo.isEmpty) return false;
    return File(p.joinAll([root.path, ...photo.split('/')])).existsSync();
  }

  Future<void> ensureLayout() async {
    await root.create(recursive: true);
    await tmpDir.create(recursive: true);
  }

  Future<GroupedWallpaperState?> readState() async => await _readJson(stateFile, GroupedWallpaperState.tryFromJsonMap, 'state.json');

  /// The slot the renderer promoted to, or null when there is none or it is
  /// stale.
  Future<GroupedWallpaperRuntime?> readRuntime() async => await _readJson(runtimeFile, GroupedWallpaperRuntime.tryFromJsonMap, 'runtime.json');

  Future<void> writeState(GroupedWallpaperState state) async {
    await ensureLayout();
    await _writeJson(stateFile, state.toJsonMap(), 'state.json');
    groupedWallpaperLog.d('state.write generation=${state.generation} status=${state.status.name} entry=${state.entryId}');
  }

  /// Removes the photos of slots that are no longer part of the queue.
  ///
  /// Only frames written before the entry-keyed cache lived under `slots/`; the
  /// call is kept so an upgraded install drops them once.
  Future<void> pruneSlots(Iterable<int> keep) async {
    if (!await slotsDir.exists()) return;
    final kept = keep.toSet();
    await for (final entity in slotsDir.list()) {
      final name = p.basename(entity.path);
      final id = int.tryParse(name);
      if (id != null && kept.contains(id)) continue;
      try {
        await entity.delete(recursive: true);
      } catch (error, stack) {
        groupedWallpaperLog.w('failed to delete the wallpaper slot $name', error, stack);
      }
    }
  }

  /// Removes every baked photo, so the renderer falls back to its placeholder.
  Future<void> clearSlots() async {
    try {
      if (await slotsDir.exists()) await slotsDir.delete(recursive: true);
      if (await framesDir.exists()) await framesDir.delete(recursive: true);
      // v1 kept one photo at the root; a state written by an older build may
      // still point at it.
      final legacy = File(p.join(root.path, GroupedWallpaperState.photoFileNameV1));
      if (await legacy.exists()) await legacy.delete();
    } catch (error, stack) {
      // Best effort: a locked file is not worth failing the sync for.
      groupedWallpaperLog.w('failed to clear the wallpaper photos', error, stack);
    }
  }

  Future<T?> _readJson<T>(File file, T? Function(Map<String, Object?> json) parse, String name) async {
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        groupedWallpaperLog.w('expected a JSON object in ${file.path}');
        return null;
      }
      final parsed = parse(decoded.map((key, value) => MapEntry(key.toString(), value)));
      if (parsed == null) groupedWallpaperLog.w('invalid $name content');
      return parsed;
    } catch (error, stack) {
      // A half-written or foreign file must never crash the wallpaper service.
      groupedWallpaperLog.w('failed to read $name', error, stack);
      return null;
    }
  }

  Future<void> _writeJson(File target, Map<String, Object?> json, String name) async {
    final tmp = File(p.join(tmpDir.path, '$name.${DateTime.now().microsecondsSinceEpoch}.tmp'));
    try {
      await tmp.writeAsString(jsonEncode(json), flush: true);
      await _replace(tmp, target);
    } catch (error, stack) {
      await _deleteQuietly(tmp);
      groupedWallpaperLog.e('failed to write $name', error, stack);
      rethrow;
    }
  }

  Future<void> _replace(File tmp, File target) async {
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // Windows cannot always replace an existing file with `rename`; Android
      // does. Deleting first keeps tests and desktop runs working.
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup; the original error is more useful.
    }
  }
}
