import 'package:aves/model/entry/entry.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Outcome of resolving a wallpaper source against the database.
///
/// The distinction matters to the UI: an empty scope is a working source that
/// currently has no photos, a missing single entry was deleted or is not an
/// image, and an unsupported scope uses filters the SQL layer cannot compile.
enum WallpaperSourceStatus {
  ready,
  empty,
  unsupported,
  missing,
}

/// Result of resolving a scope through the source repository.
///
/// [total] is only meaningful when [status] is [WallpaperSourceStatus.ready],
/// and always equals a walk of the same predicate the window query uses.
@immutable
class WallpaperSourceResolution with Equatable {
  final WallpaperSourceStatus status;
  final int total;
  final String? reason;

  const new({
    required this.status,
    this.total = 0,
    this.reason,
  });

  static WallpaperSourceResolution ready(int total) => WallpaperSourceResolution(status: WallpaperSourceStatus.ready, total: total);

  static const WallpaperSourceResolution empty = WallpaperSourceResolution(status: WallpaperSourceStatus.empty);

  static WallpaperSourceResolution unsupported(String reason) => WallpaperSourceResolution(status: WallpaperSourceStatus.unsupported, reason: reason);

  static const WallpaperSourceResolution missing = WallpaperSourceResolution(status: WallpaperSourceStatus.missing);

  bool get isReady => status == WallpaperSourceStatus.ready;

  bool get isEmpty => status == WallpaperSourceStatus.empty;

  bool get isUnsupported => status == WallpaperSourceStatus.unsupported;

  bool get isMissing => status == WallpaperSourceStatus.missing;

  @override
  List<Object?> get props => [status, total, reason];
}

/// One resolved artwork.
///
/// [offset] is the position the entry was read at within the source. The
/// controller persists/derives the next cursor from it, and retries after a
/// bake failure start from `offset + 1`.
@immutable
class WallpaperSourcePick {
  final WallpaperSourceStatus status;
  final AvesEntry? entry;
  final int total;
  final int offset;
  final String? reason;

  const new({
    required this.status,
    this.entry,
    this.total = 0,
    this.offset = -1,
    this.reason,
  });

  static WallpaperSourcePick fromResolution(WallpaperSourceResolution resolution) => WallpaperSourcePick(
    status: resolution.status,
    total: resolution.total,
    reason: resolution.reason,
  );

  bool get hasEntry => entry != null;

  @override
  String toString() => '$runtimeType{status=${status.name}, entry=${entry?.id}, total=$total, offset=$offset}';
}
