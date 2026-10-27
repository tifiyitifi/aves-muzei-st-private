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
/// <root>/state.json     # Dart-owned, read by the native renderer
/// <root>/current.png    # the baked photo
/// <root>/tmp/           # atomic-write staging
/// ```
///
/// Writes go through `tmp/` and are renamed over the destination, so the native
/// renderer never observes a truncated JSON file or PNG. The root is separate
/// from Muzei's, so the two live-wallpaper features cannot read each other's
/// files.
class GroupedWallpaperStateStore {
  static const String stateFileName = 'state.json';
  static const String tmpDirName = 'tmp';

  final Directory root;

  new(this.root);

  /// The production location: `<app files>/grouped_wallpaper`.
  static GroupedWallpaperStateStore inAppFiles(Directory filesDir) => GroupedWallpaperStateStore(Directory(p.join(filesDir.path, 'grouped_wallpaper')));

  File get stateFile => File(p.join(root.path, stateFileName));

  File get photoFile => File(p.join(root.path, GroupedWallpaperState.photoFileName));

  Directory get tmpDir => Directory(p.join(root.path, tmpDirName));

  Future<void> ensureLayout() async {
    await root.create(recursive: true);
    await tmpDir.create(recursive: true);
  }

  Future<GroupedWallpaperState?> readState() async {
    if (!await stateFile.exists()) return null;
    try {
      final raw = await stateFile.readAsString();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        groupedWallpaperLog.w('expected a JSON object in ${stateFile.path}');
        return null;
      }
      final state = GroupedWallpaperState.tryFromJsonMap(decoded.map((key, value) => MapEntry(key.toString(), value)));
      if (state == null) groupedWallpaperLog.w('invalid state.json content');
      return state;
    } catch (error, stack) {
      // A half-written or foreign file must never crash the wallpaper service.
      groupedWallpaperLog.w('failed to read state.json', error, stack);
      return null;
    }
  }

  Future<void> writeState(GroupedWallpaperState state) async {
    await ensureLayout();
    final tmp = File(p.join(tmpDir.path, '$stateFileName.${DateTime.now().microsecondsSinceEpoch}.tmp'));
    try {
      await tmp.writeAsString(jsonEncode(state.toJsonMap()), flush: true);
      await _replace(tmp, stateFile);
      groupedWallpaperLog.d('state.write generation=${state.generation} status=${state.status.name} entry=${state.entryId}');
    } catch (error, stack) {
      await _deleteQuietly(tmp);
      groupedWallpaperLog.e('failed to write state.json', error, stack);
      rethrow;
    }
  }

  Future<void> writePhoto(Uint8List bytes) async {
    await ensureLayout();
    final tmp = File(p.join(tmpDir.path, 'photo.${DateTime.now().microsecondsSinceEpoch}.tmp'));
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await _replace(tmp, photoFile);
    } catch (error, stack) {
      await _deleteQuietly(tmp);
      groupedWallpaperLog.e('failed to write the wallpaper photo', error, stack);
      rethrow;
    }
  }

  /// Removes the baked photo so the renderer falls back to its placeholder.
  Future<void> clearPhoto() async {
    try {
      if (await photoFile.exists()) await photoFile.delete();
    } catch (error, stack) {
      // Best effort: a locked file is not worth failing the sync for.
      groupedWallpaperLog.w('failed to delete the wallpaper photo', error, stack);
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
