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

  final Directory root;

  new(this.root);

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
