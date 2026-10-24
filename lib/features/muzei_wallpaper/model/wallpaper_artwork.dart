import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Paths of a slot's baked files, relative to the wallpaper root.
@immutable
class WallpaperSlotFiles with Equatable {
  static const String sharpName = 'sharp.png';
  static const String effectsHomeName = 'effects_home.png';
  static const String effectsLockName = 'effects_lock.png';
  static const String artworkName = 'art.json';

  final String sharp;
  final String effectsHome;
  final String effectsLock;

  const new({
    required this.sharp,
    required this.effectsHome,
    required this.effectsLock,
  });

  static const WallpaperSlotFiles empty = WallpaperSlotFiles(
    sharp: '',
    effectsHome: '',
    effectsLock: '',
  );

  bool get hasSharp => sharp.isNotEmpty;

  bool get hasEffects => effectsHome.isNotEmpty && effectsLock.isNotEmpty;

  Map<String, Object?> toJsonMap() => {
    'sharp': sharp,
    'effectsHome': effectsHome,
    'effectsLock': effectsLock,
  };

  static WallpaperSlotFiles fromJsonMap(Map<String, Object?> json) => WallpaperSlotFiles(
    sharp: _string(json['sharp']),
    effectsHome: _string(json['effectsHome']),
    effectsLock: _string(json['effectsLock']),
  );

  static String _string(Object? value) => value is String ? value : '';

  @override
  List<Object?> get props => [sharp, effectsHome, effectsLock];
}

/// Entry metadata and baked files for one artwork.
@immutable
class WallpaperArtwork with Equatable {
  final int entryId;
  final String uri;
  final String? title;
  final String? byline;
  final String? attribution;
  final int? dateMillis;
  final WallpaperSlotFiles files;

  /// Size of the baked sharp image, in pixels.
  ///
  /// The page lays the artwork out at its cover size so panning can reveal the
  /// parts the wallpaper crop hides; that needs the aspect ratio without waiting
  /// for a decode. Absent for history entries and for slots baked before the
  /// field existed.
  final int? width;
  final int? height;

  /// Average luminance of the baked artwork in `0..1`, as measured for the dim
  /// effect. Lets the effects preview apply the same dim curve as the bake.
  final double? darkness;

  const new({
    required this.entryId,
    required this.uri,
    this.title,
    this.byline,
    this.attribution,
    this.dateMillis,
    this.files = WallpaperSlotFiles.empty,
    this.width,
    this.height,
    this.darkness,
  });

  /// Whether the layout can size the artwork itself instead of the viewport.
  double? get aspectRatio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  WallpaperArtwork copyWith({
    int? entryId,
    String? uri,
    String? title,
    String? byline,
    String? attribution,
    int? dateMillis,
    WallpaperSlotFiles? files,
    int? width,
    int? height,
    double? darkness,
  }) => WallpaperArtwork(
    entryId: entryId ?? this.entryId,
    uri: uri ?? this.uri,
    title: title ?? this.title,
    byline: byline ?? this.byline,
    attribution: attribution ?? this.attribution,
    dateMillis: dateMillis ?? this.dateMillis,
    files: files ?? this.files,
    width: width ?? this.width,
    height: height ?? this.height,
    darkness: darkness ?? this.darkness,
  );

  Map<String, Object?> toJsonMap() => {
    'entryId': entryId,
    'uri': uri,
    if (title != null) 'title': title,
    if (byline != null) 'byline': byline,
    if (attribution != null) 'attribution': attribution,
    if (dateMillis != null) 'dateMillis': dateMillis,
    'files': files.toJsonMap(),
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (darkness != null) 'darkness': darkness,
  };

  static WallpaperArtwork? tryFromJsonMap(Map<String, Object?> json) {
    final rawEntryId = json['entryId'];
    final entryId = rawEntryId is int ? rawEntryId : (rawEntryId is num ? rawEntryId.toInt() : 0);
    final uri = json['uri'];
    if (entryId <= 0 || uri is! String || uri.isEmpty) return null;
    final rawDate = json['dateMillis'];
    final dateMillis = rawDate is int ? rawDate : (rawDate is num ? rawDate.toInt() : null);
    final width = _positiveInt(json['width']);
    final height = _positiveInt(json['height']);
    final darkness = _unitDouble(json['darkness']);
    return WallpaperArtwork(
      entryId: entryId,
      uri: uri,
      title: _nullableString(json['title']),
      byline: _nullableString(json['byline']),
      attribution: _nullableString(json['attribution']),
      dateMillis: dateMillis,
      files: json['files'] is Map
          ? WallpaperSlotFiles.fromJsonMap(
              (json['files'] as Map).map((key, value) => MapEntry(key.toString(), value)),
            )
          : WallpaperSlotFiles.empty,
      // A mismatched pair cannot describe an aspect ratio; drop both.
      width: width != null && height != null ? width : null,
      height: width != null && height != null ? height : null,
      darkness: darkness,
    );
  }

  static int? _positiveInt(Object? value) {
    final int? parsed = value is int ? value : (value is num ? value.toInt() : null);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static double? _unitDouble(Object? value) {
    if (value is! num) return null;
    final parsed = value.toDouble();
    if (parsed.isNaN || parsed.isInfinite) return null;
    return parsed.clamp(0.0, 1.0).toDouble();
  }

  static String? _nullableString(Object? value) => value is String && value.isNotEmpty ? value : null;

  @override
  List<Object?> get props => [entryId, uri, title, byline, attribution, dateMillis, files, width, height, darkness];
}

/// A baked slot: its id plus the artwork it represents.
///
/// Serialized flat (slot id alongside artwork fields) to keep the native
/// `state.json` reader small.
@immutable
class WallpaperSlot with Equatable {
  final int id;
  final WallpaperArtwork artwork;

  const new({
    required this.id,
    required this.artwork,
  });

  WallpaperSlot copyWith({
    int? id,
    WallpaperArtwork? artwork,
  }) => WallpaperSlot(
    id: id ?? this.id,
    artwork: artwork ?? this.artwork,
  );

  Map<String, Object?> toJsonMap() => {
    'id': id,
    ...artwork.toJsonMap(),
  };

  static WallpaperSlot? tryFromJsonMap(Map<String, Object?> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : (rawId is num ? rawId.toInt() : -1);
    if (id < 0) return null;
    final artwork = WallpaperArtwork.tryFromJsonMap(json);
    if (artwork == null) return null;
    return WallpaperSlot(id: id, artwork: artwork);
  }

  @override
  List<Object?> get props => [id, artwork];
}
