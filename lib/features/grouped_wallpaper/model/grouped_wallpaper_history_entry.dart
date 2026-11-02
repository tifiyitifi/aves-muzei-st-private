import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// One photo the grouped wallpaper has shown.
///
/// It is a row of the usage history, not a slot: [usedAt] is when the photo was
/// put on screen, and the group name is a snapshot so a row still reads correctly
/// after its group was renamed or deleted.
///
/// [surface] keeps the two surfaces apart: the lock screen deliberately shows a
/// different photo than the home screen, so the same entry on both surfaces is
/// two records, not one.
@immutable
class GroupedWallpaperHistoryEntry extends Equatable {
  final int entryId;
  final String groupId;
  final String groupName;
  final int groupNumber;
  final WallpaperSurface surface;

  /// Milliseconds since the epoch.
  final int usedAt;

  const new({
    required this.entryId,
    required this.groupId,
    this.groupName = '',
    this.groupNumber = 0,
    this.surface = WallpaperSurface.home,
    required this.usedAt,
  });

  @override
  List<Object?> get props => [entryId, groupId, groupName, groupNumber, surface, usedAt];
}
