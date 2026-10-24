import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/muzei_wallpaper/log.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_artwork.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_state.dart';
import 'package:path/path.dart' as p;

/// Owns the on-disk live-wallpaper directory.
///
/// Layout:
/// ```
/// <root>/state.json                 # Dart-owned
/// <root>/runtime.json               # native-owned
/// <root>/slots/<id>/sharp.png
/// <root>/slots/<id>/effects_home.png
/// <root>/slots/<id>/effects_lock.png
/// <root>/slots/<id>/art.json
/// <root>/tmp/                       # atomic-write staging
/// ```
///
/// Writes go through `tmp/` and are renamed over the destination, so the native
/// renderer never observes a truncated JSON file or PNG.
class WallpaperStateStore {
  static const String stateFileName = 'state.json';
  static const String runtimeFileName = 'runtime.json';
  static const String slotsDirName = 'slots';
  static const String tmpDirName = 'tmp';
  static const String lockFileName = 'writer.lock';

  final Directory root;

  /// Nesting depth of [runExclusive] in this isolate.
  ///
  /// Two isolates never share this counter: each one owns its own OS file lock,
  /// which is what serializes the foreground page and the background refill.
  int _lockDepth = 0;

  new(this.root);

  File get lockFile => File(p.join(root.path, lockFileName));

  /// Runs [body] while holding the wallpaper writer lock.
  ///
  /// The page and the headless refill run in different isolates: opening the app
  /// during a refill would otherwise bake two artworks into the same free slot
  /// and let the last writer win. Callers re-read `state.json` inside [body] so
  /// they act on what the other writer committed.
  ///
  /// Re-entrant within one isolate, because an advance may start a prefetch
  /// while it still holds the lock.
  Future<T> runExclusive<T>(Future<T> Function() body, {Duration timeout = const Duration(seconds: 45)}) async {
    if (_lockDepth > 0) {
      _lockDepth++;
      try {
        return await body();
      } finally {
        _lockDepth--;
      }
    }
    final handle = await _openLock(timeout);
    _lockDepth = 1;
    try {
      return await body();
    } finally {
      _lockDepth = 0;
      await _closeLock(handle);
    }
  }

  Future<RandomAccessFile?> _openLock(Duration timeout) async {
    await ensureLayout();
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final candidate = await lockFile.open(mode: FileMode.append);
      try {
        // `FileLock.exclusive` is the non-blocking mode: poll instead of
        // blocking forever, so a crashed writer can never wedge the wallpaper.
        await candidate.lock(FileLock.exclusive);
        return candidate;
      } on FileSystemException {
        await candidate.close();
        if (DateTime.now().isAfter(deadline)) {
          wallpaperLog.w('wallpaper writer lock timed out');
          return null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> _closeLock(RandomAccessFile? handle) async {
    if (handle == null) return;
    try {
      await handle.unlock();
    } on FileSystemException {
      // The lock disappears with the handle anyway.
    } finally {
      await handle.close();
    }
  }

  /// The production location: `<app files>/muzei_wallpaper`.
  static WallpaperStateStore inAppFiles(Directory filesDir) {
    return WallpaperStateStore(Directory(p.join(filesDir.path, 'muzei_wallpaper')));
  }

  File get stateFile => File(p.join(root.path, stateFileName));

  File get runtimeFile => File(p.join(root.path, runtimeFileName));

  Directory get slotsDir => Directory(p.join(root.path, slotsDirName));

  Directory get tmpDir => Directory(p.join(root.path, tmpDirName));

  Directory slotDirectory(int slotId) => Directory(p.join(slotsDir.path, '$slotId'));

  File slotFile(int slotId, String name) => File(p.join(slotDirectory(slotId).path, name));

  /// Resolves a slot path as stored in `state.json`.
  ///
  /// The page and the native renderer must both read the file the state points
  /// at, instead of rebuilding the name from the slot id, so a layout change
  /// cannot make them disagree.
  File resolveSlotPath(String relative) => File(p.join(root.path, relative));

  /// Path of a slot file as stored in `state.json`.
  ///
  /// Always POSIX-style: the native renderer resolves it against the wallpaper
  /// root with `/`, and the value must not change when tests run on Windows.
  static String relativeSlotFile(int slotId, String name) => p.posix.join(slotsDirName, '$slotId', name);

  Future<void> ensureLayout() async {
    await root.create(recursive: true);
    await slotsDir.create(recursive: true);
    await tmpDir.create(recursive: true);
  }

  Future<WallpaperState?> readState() async {
    final state = await _readJson(stateFile);
    if (state == null) return null;
    try {
      final parsed = WallpaperState.fromJsonMap(state);
      if (parsed == null) {
        wallpaperLog.w('invalid state.json version/content');
      }
      return parsed;
    } catch (error, stack) {
      wallpaperLog.w('failed to parse state.json', error, stack);
      return null;
    }
  }

  Future<void> writeState(WallpaperState state) async {
    await _writeJsonAtomic(stateFile, state.toJsonMap());
    wallpaperLog.d('state.write generation=${state.generation} current=${state.current} next=${state.next}');
  }

  Future<WallpaperRuntime?> readRuntime() async {
    final runtime = await _readJson(runtimeFile);
    if (runtime == null) return null;
    try {
      final parsed = WallpaperRuntime.fromJsonMap(runtime);
      if (parsed == null) {
        wallpaperLog.w('invalid runtime.json content');
      }
      return parsed;
    } catch (error, stack) {
      wallpaperLog.w('failed to parse runtime.json', error, stack);
      return null;
    }
  }

  Future<void> writeRuntime(WallpaperRuntime runtime) async {
    await _writeJsonAtomic(runtimeFile, runtime.toJsonMap());
    wallpaperLog.d('runtime.write generation=${runtime.generation} current=${runtime.current} next=${runtime.next}');
  }

  /// Writes one baked file and returns its final path.
  Future<File> writeSlotBytes(int slotId, String name, Uint8List bytes) async {
    await ensureLayout();
    final target = slotFile(slotId, name);
    await target.parent.create(recursive: true);
    final tmp = File(p.join(tmpDir.path, 'slot-$slotId-$name.${DateTime.now().microsecondsSinceEpoch}.tmp'));
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await _replace(tmp, target);
    } catch (error, stack) {
      await _deleteQuietly(tmp);
      wallpaperLog.e('failed to write slot file slot=$slotId name=$name', error, stack);
      rethrow;
    }
    return target;
  }

  Future<File> writeSlotArtwork(int slotId, WallpaperArtwork artwork) async {
    final target = slotFile(slotId, WallpaperSlotFiles.artworkName);
    await _writeJsonAtomic(target, artwork.toJsonMap());
    return target;
  }

  Future<void> deleteSlot(int slotId) async {
    final dir = slotDirectory(slotId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      wallpaperLog.d('slot.delete id=$slotId');
    }
  }

  Future<void> clear() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
      wallpaperLog.d('store.clear');
    }
  }

  Future<Map<String, Object?>?> _readJson(File file) async {
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        wallpaperLog.w('expected a JSON object in ${file.path}');
        return null;
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (error, stack) {
      wallpaperLog.w('failed to read ${file.path}', error, stack);
      return null;
    }
  }

  Future<void> _writeJsonAtomic(File target, Map<String, Object?> json) async {
    await ensureLayout();
    await target.parent.create(recursive: true);
    final tmp = File(p.join(tmpDir.path, '${p.basename(target.path)}.${DateTime.now().microsecondsSinceEpoch}.tmp'));
    try {
      await tmp.writeAsString(jsonEncode(json), flush: true);
      await _replace(tmp, target);
    } catch (error, stack) {
      await _deleteQuietly(tmp);
      wallpaperLog.e('failed to write ${target.path}', error, stack);
      rethrow;
    }
  }

  Future<void> _replace(File tmp, File target) async {
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // Windows cannot always replace an existing file with `rename`; Android
      // does. Deleting first keeps tests and desktop runs working.
      if (await target.exists()) {
        await target.delete();
      }
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
