import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_baker.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_bridge.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_frame_geometry.dart';
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
    GroupedFrameGeometry homeGeometry = const GroupedFrameGeometry(),
    GroupedFrameGeometry lockGeometry = const GroupedFrameGeometry(),
    Size? lockTargetSize,
    bool lockSharesHomeBase = true,
  });

  /// Bakes the lock surface's one frame into [photoPath].
  ///
  /// [photoPath] is the final image with [effects] already applied, because the
  /// decoy has no sharp original and no second effect file to fall back to.
  Future<GroupedLockFrameBake> bakeLockTo({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects effects,
    required String photoPath,
    GroupedFrameGeometry geometry = const GroupedFrameGeometry(),
  });
}

/// What one lock frame bake produced: the pixels are already in the caller's
/// file, and only the metadata travels back.
class GroupedLockFrameBake {
  final int width;
  final int height;
  final double darkness;

  const new({required this.width, required this.height, required this.darkness});
}

/// The effect image of each surface.
///
/// An identity effect draws the sharp frame, so it writes nothing. Linked
/// surfaces share the home image instead of storing the same bytes twice — but
/// only when the lock surface really draws the home base: with its own framing
/// it needs its own file, even for the identity, because that file is the
/// geometry rendering.
({GroupedFrameEffect home, GroupedFrameEffect lock}) groupedFrameEffects(WallpaperEffects home, WallpaperEffects lock, {bool lockSharesHomeBase = true}) {
  final homeEffect = home.isIdentity ? GroupedFrameEffect.none : GroupedFrameEffect.home;
  final GroupedFrameEffect lockEffect;
  if (!lockSharesHomeBase) {
    lockEffect = GroupedFrameEffect.lock;
  } else if (lock.isIdentity) {
    lockEffect = GroupedFrameEffect.none;
  } else {
    lockEffect = lock == home ? GroupedFrameEffect.home : GroupedFrameEffect.lock;
  }
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
    GroupedFrameGeometry homeGeometry = const GroupedFrameGeometry(),
    GroupedFrameGeometry lockGeometry = const GroupedFrameGeometry(),
    Size? lockTargetSize,
    bool lockSharesHomeBase = true,
  }) async {
    final bake = await baker.bake(
      entry: entry,
      targetSize: targetSize,
      home: home,
      lock: lock,
      homeGeometry: homeGeometry,
      lockGeometry: lockGeometry,
      lockTargetSize: lockTargetSize,
      lockSharesHomeBase: lockSharesHomeBase,
    );
    final effects = groupedFrameEffects(home, lock, lockSharesHomeBase: lockSharesHomeBase);
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

  @override
  Future<GroupedLockFrameBake> bakeLockTo({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects effects,
    required String photoPath,
    GroupedFrameGeometry geometry = const GroupedFrameGeometry(),
  }) async {
    // `home == lock` makes the baker render one effect pass and hand it back as
    // the home image; the lock file is that image, not a second copy.
    final bake = await baker.bake(
      entry: entry,
      targetSize: targetSize,
      home: effects,
      lock: effects,
      homeGeometry: geometry,
      lockGeometry: geometry,
    );
    await _writeAtomically(File(photoPath), bake.effectsHomePng);
    return GroupedLockFrameBake(
      width: bake.size.width.round(),
      height: bake.size.height.round(),
      darkness: bake.darkness,
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
    GroupedFrameGeometry homeGeometry = const GroupedFrameGeometry(),
    GroupedFrameGeometry lockGeometry = const GroupedFrameGeometry(),
    Size? lockTargetSize,
    bool lockSharesHomeBase = true,
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
        homeGeometry: homeGeometry,
        lockGeometry: lockGeometry,
        lockTargetSize: lockTargetSize,
        lockSharesHomeBase: lockSharesHomeBase,
      );
    }
    final written = await platform.writeFrame(
      entry: entry,
      targetSize: targetSize,
      geometry: homeGeometry,
      photoPath: photoPath,
      quality: quality,
    );
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
        homeGeometry: homeGeometry,
        lockGeometry: lockGeometry,
        lockTargetSize: lockTargetSize,
        lockSharesHomeBase: lockSharesHomeBase,
      );
    }
    final effects = groupedFrameEffects(home, lock, lockSharesHomeBase: lockSharesHomeBase);
    final homeSize = Size(written.width.toDouble(), written.height.toDouble());
    final homeDarkness = GroupedWallpaperBaker.darknessOf(written.thumbnail);
    // The lock base is a second native write only when it cannot reuse the home
    // frame; its scratch file is removed once the surface file is published.
    var lockBase = File(photoPath);
    var lockSize = homeSize;
    var lockDarkness = homeDarkness;
    try {
      if (!lockSharesHomeBase) {
        // A `.tmp` name lets the state store's sweep collect the scratch if the
        // process dies between the two writes.
        lockBase = File('$photoPath.lock.tmp');
        final lockWritten = await platform.writeFrame(
          entry: entry,
          targetSize: lockTargetSize ?? targetSize,
          geometry: lockGeometry,
          photoPath: lockBase.path,
          quality: quality,
        );
        if (lockWritten == null) {
          groupedWallpaperLog.d('frame.native lock fallback entry=${entry.id}');
          return await fallback.bakeTo(
            entry: entry,
            targetSize: targetSize,
            home: home,
            lock: lock,
            photoPath: photoPath,
            effectHomePath: effectHomePath,
            effectLockPath: effectLockPath,
            homeGeometry: homeGeometry,
            lockGeometry: lockGeometry,
            lockTargetSize: lockTargetSize,
            lockSharesHomeBase: lockSharesHomeBase,
          );
        }
        lockSize = Size(lockWritten.width.toDouble(), lockWritten.height.toDouble());
        lockDarkness = GroupedWallpaperBaker.darknessOf(lockWritten.thumbnail);
      }
      if (effects.home == GroupedFrameEffect.home) {
        await _writeAtomically(File(effectHomePath), await fallback.baker.renderEffectsFromFile(File(photoPath), homeSize, home, homeDarkness));
      }
      if (effects.lock == GroupedFrameEffect.lock) {
        if (lock.isIdentity) {
          // Identity effects still need the file when the lock has its own
          // geometry: it is that rendering, not an effect pass.
          await _moveAtomically(lockBase, File(effectLockPath));
        } else {
          await _writeAtomically(File(effectLockPath), await fallback.baker.renderEffectsFromFile(lockBase, lockSize, lock, lockDarkness));
        }
      }
    } finally {
      // The scratch is only an intermediate; a failed write must not leave it
      // behind for the frame cache to sweep much later.
      if (!lockSharesHomeBase && await lockBase.exists()) await lockBase.delete();
    }
    groupedWallpaperLog.d('frame.native entry=${entry.id} size=${written.width}x${written.height} darkness=${homeDarkness.toStringAsFixed(3)}');
    return GroupedFrameBake(
      width: written.width,
      height: written.height,
      darkness: homeDarkness,
      homeEffect: effects.home,
      lockEffect: effects.lock,
    );
  }

  @override
  Future<GroupedLockFrameBake> bakeLockTo({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects effects,
    required String photoPath,
    GroupedFrameGeometry geometry = const GroupedFrameGeometry(),
  }) async {
    if (entry.isVideo || entry.isSvg) {
      return fallback.bakeLockTo(entry: entry, targetSize: targetSize, effects: effects, photoPath: photoPath, geometry: geometry);
    }
    // The platform writes the sharp crop to a sibling scratch file; the effect
    // pass then overwrites the destination, so the stored frame is exactly what
    // the lock screen draws.
    final scratch = '$photoPath.sharp';
    final written = await platform.writeFrame(entry: entry, targetSize: targetSize, geometry: geometry, photoPath: scratch, quality: quality);
    if (written == null) {
      return fallback.bakeLockTo(entry: entry, targetSize: targetSize, effects: effects, photoPath: photoPath, geometry: geometry);
    }
    final darkness = GroupedWallpaperBaker.darknessOf(written.thumbnail);
    final size = Size(written.width.toDouble(), written.height.toDouble());
    final sharp = File(scratch);
    try {
      if (effects.isIdentity) {
        await _moveAtomically(sharp, File(photoPath));
      } else {
        final bytes = await fallback.baker.renderEffectsFromFile(sharp, size, effects, darkness);
        await _writeAtomically(File(photoPath), bytes);
      }
    } finally {
      // The scratch is only an intermediate; a failed write must not leave it
      // behind for the frame cache to sweep much later.
      if (await sharp.exists()) await sharp.delete();
    }
    groupedWallpaperLog.d('frame.lock entry=${entry.id} size=${written.width}x${written.height} darkness=${darkness.toStringAsFixed(3)}');
    return GroupedLockFrameBake(width: written.width, height: written.height, darkness: darkness);
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

/// Publishes [source] at [destination], replacing it atomically on Android.
Future<void> _moveAtomically(File source, File destination) async {
  if (source.path == destination.path) return;
  await destination.parent.create(recursive: true);
  if (await destination.exists()) await destination.delete();
  await source.rename(destination.path);
}
