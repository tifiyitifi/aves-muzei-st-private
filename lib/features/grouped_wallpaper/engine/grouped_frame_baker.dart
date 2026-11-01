import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_baker.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_bridge.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:flutter/painting.dart';

/// Which effect image one surface draws.
///
/// The rule lives here, next to both bakers, so a native frame and a Dart frame
/// always lay their files out the same way.
enum GroupedFrameEffect { none, home, lock }

/// What one baked frame is: its size, its darkness and its effect images.
class GroupedFrameBake {
  final int width;
  final int height;

  /// Average luminance of the sharp frame, in `0..1`.
  final double darkness;

  /// The effect image the home surface draws.
  final GroupedFrameEffect homeEffect;

  /// The effect image the lock surface draws.
  final GroupedFrameEffect lockEffect;

  const new({
    required this.width,
    required this.height,
    required this.darkness,
    required this.homeEffect,
    required this.lockEffect,
  });
}

/// Bakes one frame into the files the native renderer reads.
///
/// The engine owns *which* photo and *which* key; a baker only owns the pixels
/// in `photoPath` and, when the effects are not the identity, the effect files.
abstract interface class GroupedFrameBaker {
  Future<GroupedFrameBake> bakeTo({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects home,
    required WallpaperEffects lock,
    required String photoPath,
    required String effectHomePath,
    required String effectLockPath,
  });
}

/// The effect image of each surface.
///
/// An identity effect draws the sharp frame, so it writes nothing. Linked
/// surfaces share the home image instead of storing the same bytes twice.
({GroupedFrameEffect home, GroupedFrameEffect lock}) groupedFrameEffects(WallpaperEffects home, WallpaperEffects lock) {
  final homeEffect = home.isIdentity ? GroupedFrameEffect.none : GroupedFrameEffect.home;
  final lockEffect = lock.isIdentity
      ? GroupedFrameEffect.none
      : lock == home
          ? GroupedFrameEffect.home
          : GroupedFrameEffect.lock;
  return (home: homeEffect, lock: lockEffect);
}

/// Bakes in Dart, with Flutter's decoders and the Skia effect pipeline.
///
/// This is the fallback for hosts without the service (desktop, tests) and for
/// entries the platform cannot decode, so the engine always has one working
/// path.
class SkiaFrameBaker implements GroupedFrameBaker {
  final GroupedWallpaperBaker baker;

  new([GroupedWallpaperBaker? baker]) : baker = baker ?? GroupedWallpaperBaker();

  @override
  Future<GroupedFrameBake> bakeTo({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects home,
    required WallpaperEffects lock,
    required String photoPath,
    required String effectHomePath,
    required String effectLockPath,
  }) async {
    final bake = await baker.bake(entry: entry, targetSize: targetSize, home: home, lock: lock);
    final effects = groupedFrameEffects(home, lock);
    await _writeAtomically(File(photoPath), bake.sharpPng);
    if (effects.home == GroupedFrameEffect.home) {
      await _writeAtomically(File(effectHomePath), bake.effectsHomePng);
    }
    if (effects.lock == GroupedFrameEffect.lock) {
      await _writeAtomically(File(effectLockPath), bake.effectsLockPng);
    }
    return GroupedFrameBake(
      width: bake.size.width.round(),
      height: bake.size.height.round(),
      darkness: bake.darkness,
      homeEffect: effects.home,
      lockEffect: effects.lock,
    );
  }
}

/// Bakes the pixels on the platform side and keeps the effect pass in Dart.
///
/// Decoding, covering and encoding a wallpaper frame is pure bitmap work, and
/// doing it here removes the PNG encode/decode round trip the Dart path pays.
/// Effect rendering stays in [SkiaFrameBaker]: its math is shared with the
/// effects page preview, so a second implementation would let the two drift.
class NativeFrameBaker implements GroupedFrameBaker {
  final GroupedWallpaperPlatform platform;

  /// The Dart path, used verbatim when the platform cannot bake this entry.
  final SkiaFrameBaker fallback;

  new(this.platform, {SkiaFrameBaker? fallback}) : fallback = fallback ?? SkiaFrameBaker();

  /// Quality of the baked WebP: high enough that the wallpaper shows no
  /// compression artefacts, small enough to cut the frame cache several times.
  static const int quality = 95;

  @override
  Future<GroupedFrameBake> bakeTo({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects home,
    required WallpaperEffects lock,
    required String photoPath,
    required String effectHomePath,
    required String effectLockPath,
  }) async {
    // The platform's image pipeline has no video thumbnail settings, and SVG is
    // rasterized by the Dart region provider, so both keep the Dart path.
    if (entry.isVideo || entry.isSvg) {
      return fallback.bakeTo(
        entry: entry,
        targetSize: targetSize,
        home: home,
        lock: lock,
        photoPath: photoPath,
        effectHomePath: effectHomePath,
        effectLockPath: effectLockPath,
      );
    }
    final written = await platform.writeFrame(entry: entry, targetSize: targetSize, photoPath: photoPath, quality: quality);
    if (written == null) {
      // No service, an undecodable format or a failing channel: the fallback is
      // the contract, not a degraded mode.
      groupedWallpaperLog.d('frame.native fallback entry=${entry.id} target=$targetSize');
      return fallback.bakeTo(
        entry: entry,
        targetSize: targetSize,
        home: home,
        lock: lock,
        photoPath: photoPath,
        effectHomePath: effectHomePath,
        effectLockPath: effectLockPath,
      );
    }
    final darkness = GroupedWallpaperBaker.darknessOf(written.thumbnail);
    final effects = groupedFrameEffects(home, lock);
    final size = Size(written.width.toDouble(), written.height.toDouble());
    if (effects.home == GroupedFrameEffect.home) {
      await _writeAtomically(File(effectHomePath), await fallback.baker.renderEffectsFromFile(File(photoPath), size, home, darkness));
    }
    if (effects.lock == GroupedFrameEffect.lock) {
      await _writeAtomically(File(effectLockPath), await fallback.baker.renderEffectsFromFile(File(photoPath), size, lock, darkness));
    }
    groupedWallpaperLog.d('frame.native entry=${entry.id} size=${written.width}x${written.height} darkness=${darkness.toStringAsFixed(3)}');
    return GroupedFrameBake(
      width: written.width,
      height: written.height,
      darkness: darkness,
      homeEffect: effects.home,
      lockEffect: effects.lock,
    );
  }
}

/// Writes through a temporary file, so a failure never leaves half a frame the
/// renderer could upload.
Future<void> _writeAtomically(File file, Uint8List bytes) async {
  await file.parent.create(recursive: true);
  // A unique staging name: the app engine and the background engine can bake the
  // same photo at the same time, and a shared `.tmp` would interleave.
  final tmp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    await tmp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  } catch (error, stack) {
    if (await tmp.exists()) await tmp.delete();
    groupedWallpaperLog.e('failed to write the wallpaper frame ${file.path}', error, stack);
    rethrow;
  }
}
