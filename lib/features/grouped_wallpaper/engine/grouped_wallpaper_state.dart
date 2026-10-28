import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// What the grouped wallpaper is showing, and why.
///
/// [locked] and [disabled] keep the frame on screen: the wallpaper is not
/// following the group, so the last photo stays instead of blanking. The other
/// states all mean "no photo", so the native renderer draws its placeholder
/// instead of a stale image.
enum GroupedWallpaperStatus {
  /// A baked photo is on screen.
  ready,

  /// The group is locked: the current frame stays, nothing new is baked.
  locked,

  /// The grouped wallpaper is turned off: the last frame stays, nothing new is
  /// baked, and the wallpaper the system shows is left untouched.
  disabled,

  /// The group resolves to no image.
  emptyGroup,

  /// Reading, querying, baking or writing failed.
  unavailable;

  /// Whether the renderer must keep showing the photo it already has.
  bool get keepsFrame => this == locked || this == disabled;

  static GroupedWallpaperStatus? tryParse(Object? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// What one sync did, for the page to report.
enum GroupedWallpaperSyncResult {
  /// A photo was baked and is now on screen.
  baked,

  /// The group resolves to no image: the placeholder is on screen.
  empty,

  /// The group is locked, so its current frame was kept.
  locked,

  /// The grouped wallpaper is turned off: its last frame was kept.
  disabled,

  /// The frame already matched the saved group: nothing was written.
  unchanged,

  /// The grouped wallpaper is not the system wallpaper: nothing was written.
  notActive,

  /// Reading, querying, baking or writing failed: the placeholder is on screen.
  failed,
}

/// Dart-owned `state.json` of the grouped wallpaper.
///
/// This is the contract between the Flutter engine and the native renderer: only
/// Dart writes it, and the native side only reads it. It also carries what the
/// notification shows (group number, group name, entry, count, lock), so the
/// service never has to ask the app for text it cannot localize itself.
///
/// Parsing is deliberately tolerant: a state file written by another version, or
/// truncated by a crash, must leave the wallpaper on its placeholder instead of
/// crashing the service.
@immutable
class GroupedWallpaperState extends Equatable {
  static const int currentVersion = 1;

  /// Relative path of the baked photo, resolved against the state root.
  static const String photoFileName = 'current.png';

  final int version;

  /// Bumped on every write, so the native side can tell a stale read apart.
  final int generation;

  final GroupedWallpaperStatus status;
  final String groupId;
  final int groupNumber;

  /// Display text, not the stored `@arbKey`: the native side cannot localize.
  final String groupName;

  /// Number of images the group currently resolves to.
  final int count;

  final int? entryId;
  final String entryTitle;

  /// Relative photo path, empty when there is nothing to draw.
  final String photo;

  final int width;
  final int height;
  final int bakedAt;

  const new({
    this.version = currentVersion,
    this.generation = 0,
    required this.status,
    this.groupId = '',
    this.groupNumber = 0,
    this.groupName = '',
    this.count = 0,
    this.entryId,
    this.entryTitle = '',
    this.photo = '',
    this.width = 0,
    this.height = 0,
    this.bakedAt = 0,
  });

  /// Whether the state points at a baked frame, whatever the status: a locked
  /// group keeps showing the photo it froze on.
  bool get hasPhoto => entryId != null && photo.isNotEmpty;

  /// The state before anything was baked for [group]: the renderer shows its
  /// placeholder until the first sync.
  factory pending({required WallpaperGroup group, required String groupName, int generation = 0}) => GroupedWallpaperState(
        generation: generation,
        status: GroupedWallpaperStatus.unavailable,
        groupId: group.id,
        groupNumber: group.number,
        groupName: groupName,
      );

  GroupedWallpaperState copyWith({
    int? generation,
    GroupedWallpaperStatus? status,
    String? groupId,
    int? groupNumber,
    String? groupName,
    int? count,
    int? entryId,
    String? entryTitle,
    String? photo,
    int? width,
    int? height,
    int? bakedAt,
  }) => GroupedWallpaperState(
        version: version,
        generation: generation ?? this.generation,
        status: status ?? this.status,
        groupId: groupId ?? this.groupId,
        groupNumber: groupNumber ?? this.groupNumber,
        groupName: groupName ?? this.groupName,
        count: count ?? this.count,
        entryId: entryId ?? this.entryId,
        entryTitle: entryTitle ?? this.entryTitle,
        photo: photo ?? this.photo,
        width: width ?? this.width,
        height: height ?? this.height,
        bakedAt: bakedAt ?? this.bakedAt,
      );

  Map<String, Object?> toJsonMap() => {
        'version': version,
        'generation': generation,
        'status': status.name,
        'groupId': groupId,
        'groupNumber': groupNumber,
        'groupName': groupName,
        'count': count,
        'entryId': entryId,
        'entryTitle': entryTitle,
        'photo': photo,
        'width': width,
        'height': height,
        'bakedAt': bakedAt,
      };

  static GroupedWallpaperState? tryFromJsonMap(Map<String, Object?> json) {
    if (_int(json['version']) != currentVersion) return null;
    final status = GroupedWallpaperStatus.tryParse(json['status']);
    if (status == null) return null;

    final entryId = _int(json['entryId']);
    final photo = _string(json['photo']);
    // `ready` without a photo is a contradiction: show the placeholder instead
    // of asking the renderer to load a file that is not there. `locked` and
    // `disabled` legitimately keep no frame when nothing was ever baked.
    final normalized = status == GroupedWallpaperStatus.ready && (photo.isEmpty || entryId == null) ? GroupedWallpaperStatus.unavailable : status;
    final drawsFrame = normalized == GroupedWallpaperStatus.ready || normalized.keepsFrame;
    final hasFrame = drawsFrame && photo.isNotEmpty && entryId != null;

    return GroupedWallpaperState(
      generation: _int(json['generation']) ?? 0,
      status: normalized,
      groupId: _string(json['groupId']),
      groupNumber: _int(json['groupNumber']) ?? 0,
      groupName: _string(json['groupName']),
      count: _int(json['count']) ?? 0,
      entryId: hasFrame ? entryId : null,
      entryTitle: _string(json['entryTitle']),
      photo: hasFrame ? photo : '',
      width: _int(json['width']) ?? 0,
      height: _int(json['height']) ?? 0,
      bakedAt: _int(json['bakedAt']) ?? 0,
    );
  }

  static int? _int(Object? value) => value is int ? value : (value is num ? value.toInt() : null);

  static String _string(Object? value) => value is String ? value : '';

  @override
  List<Object?> get props => [version, generation, status, groupId, groupNumber, groupName, count, entryId, entryTitle, photo, width, height, bakedAt];
}
