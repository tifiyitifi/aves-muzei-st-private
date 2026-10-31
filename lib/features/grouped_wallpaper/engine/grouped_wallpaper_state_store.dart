import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:path/path.dart' as p;

/// Owns the grouped wallpaper's on-disk directory.
///
/// Layout:
/// ```
/// <root>/state.json              # Dart-owned, read by the native renderer
/// <root>/runtime.json            # native-owned: the slot the renderer promoted to
/// <root>/lock_request.json       # native-owned: a lock tapped while the app slept
/// <root>/slots/<id>/photo.png    # one baked photo per queue slot
/// <root>/tmp/                    # atomic-write staging
/// ```
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

  Directory get tmpDir => Directory(p.join(root.path, tmpDirName));

  /// Photo file of slot [id], named [name].
  File slotPhoto(int id, {String name = slotPhotoFileName}) => File(p.join(slotsDir.path, '$id', name));

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

  /// Writes one slot's photo and returns its path relative to the root.
  Future<String> writeSlotPhoto(int id, Uint8List bytes, {String name = slotPhotoFileName}) async {
    await ensureLayout();
    final target = slotPhoto(id, name: name);
    await target.parent.create(recursive: true);
    final tmp = File(p.join(tmpDir.path, 'slot.$id.$name.${DateTime.now().microsecondsSinceEpoch}.tmp'));
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await _replace(tmp, target);
      // POSIX separators: the native renderer resolves this against the root and
      // must not depend on the platform that wrote it.
      return '$slotsDirName/$id/$name';
    } catch (error, stack) {
      await _deleteQuietly(tmp);
      groupedWallpaperLog.e('failed to write the wallpaper photo of slot $id', error, stack);
      rethrow;
    }
  }

  /// Removes the photos of slots that are no longer part of the queue.
  ///
  /// A dropped slot must not keep megabytes around, and a later bake reuses the
  /// id: a stale file would be read as the new photo if a write ever failed.
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
