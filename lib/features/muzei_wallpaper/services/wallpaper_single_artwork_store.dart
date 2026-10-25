import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/muzei_wallpaper/log.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_single_artwork.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:path/path.dart' as p;

/// Why a single artwork could not be copied.
enum WallpaperSingleCopyFailure {
  /// The copy would not fit next to the existing files.
  noSpace,

  /// Reading the original or writing the copy failed.
  failed,
}

class WallpaperSingleCopyException implements Exception {
  final WallpaperSingleCopyFailure failure;
  final Object? cause;
  final int? freeBytes, requiredBytes;

  const new(this.failure, {this.cause, this.freeBytes, this.requiredBytes});

  bool get isNoSpace => failure == WallpaperSingleCopyFailure.noSpace;

  @override
  String toString() => 'WallpaperSingleCopyException(${failure.name}, free=$freeBytes, required=$requiredBytes, cause=$cause)';
}

/// Keeps one copy of the chosen single artwork under the wallpaper root.
///
/// The wallpaper outlives the gallery: deleting the original photo must not
/// blank it, so the bytes are copied first and the scope stores the copy's
/// metadata. Only one copy exists at a time (`source/single.*`), and it is kept
/// across source changes: the chosen photo may no longer exist in the library,
/// so switching back to it must not require picking it again. Choosing another
/// artwork is what replaces it.
class WallpaperSingleArtworkStore {
  static const String sourceDirName = 'source';

  /// Headroom kept free on top of the copy itself.
  ///
  /// The wallpaper also bakes slot PNGs while the copy is being written; a copy
  /// that fills the volume would make the bake fail instead of the copy.
  static const int spaceMarginBytes = 64 * 1024 * 1024;

  final Directory root;

  /// Injected in tests; production reads the original through the media
  /// pipeline and asks the platform for free space.
  final Future<Uint8List> Function(AvesEntry entry)? fetchBytes;
  final Future<int?> Function(String path)? freeSpace;

  new(
    this.root, {
    this.fetchBytes,
    this.freeSpace,
  });

  Directory get sourceDir => Directory(p.join(root.path, sourceDirName));

  File resolve(String relativePath) => File(p.join(root.path, relativePath));

  /// Copies [entry] and replaces any previous copy.
  ///
  /// The previous copy is only removed after the new bytes are in place, so a
  /// failed read or write leaves the current wallpaper intact.
  Future<WallpaperSingleArtwork> copy(AvesEntry entry) async {
    final Uint8List bytes;
    try {
      bytes = await (fetchBytes ?? mediaFetchService.getOriginalBytes)(entry);
    } catch (error, stack) {
      wallpaperLog.w('failed to read single artwork entry=${entry.id}', error, stack);
      throw WallpaperSingleCopyException(WallpaperSingleCopyFailure.failed, cause: error);
    }
    if (bytes.isEmpty) {
      throw const WallpaperSingleCopyException(WallpaperSingleCopyFailure.failed, cause: 'empty bytes');
    }

    final free = await _availableSpace();
    final required = bytes.length + spaceMarginBytes;
    if (free != null && free < required) {
      wallpaperLog.w('not enough space for a single artwork copy free=$free required=$required');
      throw WallpaperSingleCopyException(WallpaperSingleCopyFailure.noSpace, freeBytes: free, requiredBytes: required);
    }

    // The platform re-encodes formats Flutter cannot decode, so the copy's MIME
    // type and orientation are what the bytes really are, not what the original
    // claimed. Passthrough formats keep their metadata verbatim.
    final passthrough = _passthroughMimes.contains(entry.mimeType);
    final mimeType = passthrough ? entry.mimeType : _encodedMime(bytes);
    final rotationDegrees = passthrough ? entry.rotationDegrees : 0;
    final isFlipped = passthrough && entry.isFlipped;
    final isAnimated = passthrough && entry.isAnimated;
    final (width, height) = passthrough || !entry.isRotated ? (entry.width, entry.height) : (entry.height, entry.width);
    final extension = _extensionFor(entry, mimeType: mimeType, passthrough: passthrough);
    final relativePath = p.posix.join(sourceDirName, 'single.$extension');
    final target = resolve(relativePath);

    try {
      await target.parent.create(recursive: true);
      final tmp = File(p.join(target.parent.path, '.single.$extension.tmp'));
      try {
        await tmp.writeAsBytes(bytes, flush: true);
        await _replace(tmp, target);
      } catch (error) {
        await _deleteQuietly(tmp);
        rethrow;
      }
      await _deleteOthers(target);
    } catch (error, stack) {
      wallpaperLog.e('failed to write the single artwork copy entry=${entry.id}', error, stack);
      throw WallpaperSingleCopyException(WallpaperSingleCopyFailure.failed, cause: error);
    }

    final artwork = WallpaperSingleArtwork(
      relativePath: relativePath,
      entryId: entry.id,
      mimeType: mimeType,
      title: entry.bestTitle,
      width: width,
      height: height,
      rotationDegrees: rotationDegrees,
      isFlipped: isFlipped,
      isAnimated: isAnimated,
      sizeBytes: bytes.length,
    );
    wallpaperLog.i('single artwork copied entry=${entry.id} path=$relativePath bytes=${bytes.length}');
    return artwork;
  }

  Future<int?> _availableSpace() async {
    try {
      final freeSpace = this.freeSpace;
      if (freeSpace != null) return await freeSpace(root.path);
      // The platform call only reads the path, so an ad-hoc volume wrapper is
      // enough and keeps the copy anchored to the wallpaper root's volume.
      return await storageService.getFreeSpace(
        StorageVolume(
          mediaStoreVolumeName: null,
          description: null,
          isPrimary: true,
          isRemovable: false,
          path: root.path,
          state: 'mounted',
        ),
      );
    } catch (error, stack) {
      // Free space is advisory: an unknown value must not block the copy.
      wallpaperLog.w('failed to read free space for the single artwork copy', error, stack);
      return null;
    }
  }

  /// Deletes the other copies, so only [kept] remains.
  Future<void> _deleteOthers(File kept) async {
    await for (final entity in sourceDir.list()) {
      // The kept path was built with native separators while the snapshot path is
      // POSIX-style; compare canonical paths, not strings.
      if (p.equals(entity.path, kept.path)) continue;
      try {
        await entity.delete(recursive: true);
      } catch (error, stack) {
        wallpaperLog.w('failed to delete an old single artwork copy path=${entity.path}', error, stack);
      }
    }
  }

  static Future<void> _replace(File tmp, File target) async {
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // Windows cannot replace an existing file with `rename`; Android can.
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup; the original error is more useful.
    }
  }

  /// Formats the platform streams without re-encoding (mirrors
  /// `MimeTypes.handleEncodedBytesInFlutter` on the native side).
  static const Set<String> _passthroughMimes = {
    MimeTypes.jpeg,
    MimeTypes.png,
    MimeTypes.gif,
    MimeTypes.webp,
    MimeTypes.bmp,
    MimeTypes.bmpX,
    MimeTypes.wbmp,
    MimeTypes.ico,
    MimeTypes.icoX,
    MimeTypes.svg,
  };

  /// The MIME type of the bytes the platform produced for a re-encoded format.
  ///
  /// `BitmapUtils` compresses to PNG when the bitmap has alpha and to JPEG
  /// otherwise, so the trailer's format byte is not needed to tell them apart.
  static String _encodedMime(Uint8List bytes) {
    const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length >= pngSignature.length) {
      var isPng = true;
      for (var i = 0; i < pngSignature.length; i++) {
        if (bytes[i] != pngSignature[i]) {
          isPng = false;
          break;
        }
      }
      if (isPng) return MimeTypes.png;
    }
    return MimeTypes.jpeg;
  }

  static String _extensionFor(AvesEntry entry, {required String mimeType, required bool passthrough}) {
    if (passthrough) {
      final extension = entry.extension;
      if (extension != null && extension.length > 1) return extension.substring(1).toLowerCase();
    }
    return switch (mimeType) {
      MimeTypes.jpeg => 'jpg',
      MimeTypes.png => 'png',
      MimeTypes.gif => 'gif',
      MimeTypes.webp => 'webp',
      MimeTypes.bmp || MimeTypes.bmpX => 'bmp',
      MimeTypes.wbmp => 'wbmp',
      MimeTypes.ico || MimeTypes.icoX => 'ico',
      MimeTypes.svg => 'svg',
      _ => 'img',
    };
  }
}
