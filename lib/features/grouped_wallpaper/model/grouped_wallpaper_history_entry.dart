import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// One photo the grouped wallpaper has shown.
///
/// It is a row of the usage history, not a slot: [usedAt] is when the photo was
/// put on screen, and the group name is a snapshot so a row still reads correctly
/// after its group was renamed or deleted.
@immutable
class GroupedWallpaperHistoryEntry extends Equatable {
  final int entryId;
  final String groupId;
  final String groupName;
  final int groupNumber;

  /// Milliseconds since the epoch.
  final int usedAt;

  const new({
    required this.entryId,
    required this.groupId,
    this.groupName = '',
    this.groupNumber = 0,
    required this.usedAt,
  });

  @override
  List<Object?> get props => [entryId, groupId, groupName, groupNumber, usedAt];
}
