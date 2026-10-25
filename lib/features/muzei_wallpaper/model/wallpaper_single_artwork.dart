import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// What the wallpaper needs to keep using one copied artwork after the original
/// photo is gone.
///
/// The copy lives under the wallpaper root, so [relativePath] is POSIX-style and
/// resolved against that root by both the repository and the native renderer.
/// The metadata is the entry as the bake saw it: a copied file has no catalog
/// row, and re-reading EXIF from the copy would lose user rotation and flip.
@immutable
class WallpaperSingleArtwork with Equatable {
  final String relativePath;
  final int entryId;
  final String mimeType;
  final String? title;
  final int width;
  final int height;
  final int rotationDegrees;
  final bool isFlipped;
  final bool isAnimated;
  final int sizeBytes;

  const new({
    required this.relativePath,
    required this.entryId,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.sizeBytes,
    this.title,
    this.rotationDegrees = 0,
    this.isFlipped = false,
    this.isAnimated = false,
  });

  Map<String, Object?> toJsonMap() => {
    'relativePath': relativePath,
    'entryId': entryId,
    'mimeType': mimeType,
    if (title != null) 'title': title,
    'width': width,
    'height': height,
    'rotationDegrees': rotationDegrees,
    'isFlipped': isFlipped,
    'isAnimated': isAnimated,
    'sizeBytes': sizeBytes,
  };

  static WallpaperSingleArtwork? tryFromJsonMap(Map<String, Object?> json) {
    final relativePath = _string(json['relativePath']);
    final mimeType = _string(json['mimeType']);
    final entryId = _int(json['entryId']);
    final width = _int(json['width']);
    final height = _int(json['height']);
    final sizeBytes = _int(json['sizeBytes']);
    if (relativePath == null || mimeType == null || entryId == null || entryId <= 0) return null;
    if (!mimeType.startsWith('image/') || width == null || width <= 0 || height == null || height <= 0) return null;
    // A persisted path is only ever one the store wrote under its own root.
    if (relativePath.startsWith('/') || relativePath.split('/').contains('..')) return null;
    final rotation = _int(json['rotationDegrees']) ?? 0;
    return WallpaperSingleArtwork(
      relativePath: relativePath,
      entryId: entryId,
      mimeType: mimeType,
      title: _string(json['title']),
      width: width,
      height: height,
      rotationDegrees: rotation % 360,
      isFlipped: json['isFlipped'] == true,
      isAnimated: json['isAnimated'] == true,
      sizeBytes: sizeBytes != null && sizeBytes > 0 ? sizeBytes : 0,
    );
  }

  static String? _string(Object? value) => value is String && value.isNotEmpty ? value : null;

  static int? _int(Object? value) => value is int ? value : (value is num ? value.toInt() : null);

  @override
  List<Object?> get props => [relativePath, entryId, mimeType, title, width, height, rotationDegrees, isFlipped, isAnimated, sizeBytes];
}
