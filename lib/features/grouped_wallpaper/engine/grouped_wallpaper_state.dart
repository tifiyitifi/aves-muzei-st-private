import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
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

/// One baked photo the renderer can promote to.
///
/// Slots are the promotion queue: the native renderer moves to [GroupedWallpaperState.next]
/// on a wallpaper tap without waiting for Flutter, and Dart bakes the slot it
/// left behind. [id] is stable while the slot exists, so the renderer can keep
/// the texture it already uploaded; [entryId] and [photo] tell it that the slot
/// was re-baked with another image.
@immutable
class GroupedWallpaperSlot extends Equatable {
  final int id;
  final int entryId;
  final String uri;
  final String title;

  /// Photo path relative to the state root.
  final String photo;

  /// Baked home/lock effect paths, relative to the state root.
  ///
  /// Empty when the effect is the identity: the renderer then falls back to
  /// [photo], so an untouched group never writes a second copy of the same PNG.
  final String effectHome;
  final String effectLock;

  final int width;
  final int height;

  /// Average luminance of the sharp frame, in `0..1`, used by the effects
  /// preview to reproduce the baked dim.
  final double darkness;

  const new({
    required this.id,
    required this.entryId,
    required this.uri,
    this.title = '',
    required this.photo,
    this.effectHome = '',
    this.effectLock = '',
    this.width = 0,
    this.height = 0,
    this.darkness = .5,
  });

  double? get aspectRatio => width > 0 && height > 0 ? width / height : null;

  Map<String, Object?> toJsonMap() => {
        'id': id,
        'entryId': entryId,
        'uri': uri,
        'title': title,
        'photo': photo,
        'effectHome': effectHome,
        'effectLock': effectLock,
        'width': width,
        'height': height,
        'darkness': darkness,
      };

  static GroupedWallpaperSlot? tryFromJsonMap(Map<String, Object?> json) {
    final id = _slotInt(json['id']);
    final entryId = _slotInt(json['entryId']);
    final photo = _slotString(json['photo']);
    if (id == null || id < 0 || entryId == null || photo.isEmpty) return null;
    return GroupedWallpaperSlot(
      id: id,
      entryId: entryId,
      uri: _slotString(json['uri']),
      title: _slotString(json['title']),
      photo: photo,
      effectHome: _slotString(json['effectHome']),
      effectLock: _slotString(json['effectLock']),
      width: _slotInt(json['width']) ?? 0,
      height: _slotInt(json['height']) ?? 0,
      darkness: _slotDouble(json['darkness']) ?? .5,
    );
  }

  static int? _slotInt(Object? value) => value is int ? value : (value is num ? value.toInt() : null);

  static double? _slotDouble(Object? value) => value is num ? value.toDouble().clamp(0.0, 1.0) : null;

  static String _slotString(Object? value) => value is String ? value : '';

  @override
  List<Object?> get props => [id, entryId, uri, title, photo, effectHome, effectLock, width, height, darkness];
}

/// One photo the wallpaper has shown, for the "recently shown" exclusion and for
/// the page to fall back on when the queue is empty.
///
/// Only metadata: the baked path belongs to a slot, and a later bake recycles that
/// slot, so a stored path would silently resolve to another photo.
@immutable
class GroupedWallpaperRecentEntry extends Equatable {
  final int entryId;
  final String uri;
  final String title;

  /// The group the photo belonged to, so "previous photo" never jumps into
  /// another group's history.
  final String groupId;

  const new({
    required this.entryId,
    this.uri = '',
    this.title = '',
    this.groupId = '',
  });

  Map<String, Object?> toJsonMap() => {
        'entryId': entryId,
        'uri': uri,
        'title': title,
        'groupId': groupId,
      };

  static GroupedWallpaperRecentEntry? tryFromJsonMap(Map<String, Object?> json) {
    final entryId = GroupedWallpaperSlot._slotInt(json['entryId']);
    if (entryId == null || entryId <= 0) return null;
    return GroupedWallpaperRecentEntry(
      entryId: entryId,
      uri: GroupedWallpaperSlot._slotString(json['uri']),
      title: GroupedWallpaperSlot._slotString(json['title']),
      groupId: GroupedWallpaperSlot._slotString(json['groupId']),
    );
  }

  @override
  List<Object?> get props => [entryId, uri, title, groupId];
}

/// Dart-owned `state.json` of the grouped wallpaper.
///
/// This is the contract between the Flutter engine and the native renderer: only
/// Dart writes it, and the native side writes [GroupedWallpaperRuntime] instead.
/// It also carries what the notification shows (group number, group name, entry,
/// count, status), so the service never has to ask the app for text it cannot
/// localize itself.
///
/// [current] → [next] → [next2] is the promotion queue. The renderer promotes
/// [next] on a wallpaper tap and [next2] on the following one, so two consecutive
/// taps need no bake; Dart refills the freed slots afterwards.
///
/// Parsing is deliberately tolerant: a state file written by another version, or
/// truncated by a crash, must leave the wallpaper on its placeholder instead of
/// crashing the service.
@immutable
class GroupedWallpaperState extends Equatable {
  /// v2 added the slot queue; v3 added the ordering metadata ([recent],
  /// [cursor], [newestEntryId]); v4 added [paused] and the group id of a recent
  /// entry. Older files are read with those at their defaults, so an upgrade
  /// never loses the frame on screen. [notification] was added afterwards without
  /// a version bump: a file without it means "on", which is what those builds did.
  static const int currentVersion = 4;

  /// How many recently shown photos are remembered.
  ///
  /// The random ordering rejects them, so a group larger than this walks its
  /// whole library before repeating, while a small group repeats rather than
  /// blanking. Metadata only, so the cost is negligible.
  static const int maxRecent = 32;

  /// The single photo file a v1 state pointed at.
  static const String photoFileNameV1 = 'current.png';

  final int version;

  /// Bumped on every write, so the native side can tell a stale runtime apart.
  final int generation;

  final GroupedWallpaperStatus status;
  final String groupId;
  final int groupNumber;

  /// Display text, not the stored `@arbKey`: the native side cannot localize.
  final String groupName;

  /// Number of images the group currently resolves to.
  final int count;

  final int current;
  final int next;
  final int next2;
  final List<GroupedWallpaperSlot> slots;

  /// Photos the wallpaper has shown, newest first.
  final List<GroupedWallpaperRecentEntry> recent;

  /// Position of the next in-order pick within the group.
  final int cursor;

  /// Highest entry id shown, so photos added afterwards are served first.
  final int newestEntryId;

  /// Ordering the queue was baked with, for continuity across restarts.
  final GroupedWallpaperOrdering ordering;

  /// Gestures the renderer acts on without asking Dart.
  final GroupedWallpaperGestures gestures;

  /// Whether the wallpaper is frozen: it keeps the current photo and the
  /// renderer refuses to promote, so neither a tap nor an interval advances it.
  ///
  /// This is deliberately separate from [GroupedWallpaperStatus.locked], which
  /// is the visible range's own lock.
  final bool paused;

  /// Whether the user lets the wallpaper show its notification bar.
  ///
  /// It travels with the state because the service owns the bar: with this off it
  /// posts nothing and never promotes itself to a foreground service.
  final bool notification;

  final int bakedAt;

  const new({
    this.version = currentVersion,
    this.generation = 0,
    required this.status,
    this.groupId = '',
    this.groupNumber = 0,
    this.groupName = '',
    this.count = 0,
    this.current = -1,
    this.next = -1,
    this.next2 = -1,
    this.slots = const [],
    this.recent = const [],
    this.cursor = 0,
    this.newestEntryId = 0,
    this.ordering = GroupedWallpaperOrdering.defaultOrdering,
    this.gestures = const GroupedWallpaperGestures(),
    this.paused = false,
    this.notification = true,
    this.bakedAt = 0,
  });

  GroupedWallpaperSlot? slotById(int id) {
    for (final slot in slots) {
      if (slot.id == id) return slot;
    }
    return null;
  }

  GroupedWallpaperSlot? get currentSlot => slotById(current);

  GroupedWallpaperSlot? get nextSlot => slotById(next);

  GroupedWallpaperSlot? get next2Slot => slotById(next2);

  /// Whether the state points at a baked frame, whatever the status: a locked or
  /// turned-off group keeps showing the photo it stopped on.
  bool get hasPhoto => currentSlot != null;

  /// How many slots are queued, current included.
  int get queueLength => [current, next, next2].where((id) => id >= 0).length;

  int? get entryId => currentSlot?.entryId;

  String get entryTitle => currentSlot?.title ?? '';

  int get width => currentSlot?.width ?? 0;

  int get height => currentSlot?.height ?? 0;

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
    int? version,
    int? generation,
    GroupedWallpaperStatus? status,
    String? groupId,
    int? groupNumber,
    String? groupName,
    int? count,
    int? current,
    int? next,
    int? next2,
    List<GroupedWallpaperSlot>? slots,
    List<GroupedWallpaperRecentEntry>? recent,
    int? cursor,
    int? newestEntryId,
    GroupedWallpaperOrdering? ordering,
    GroupedWallpaperGestures? gestures,
    bool? paused,
    bool? notification,
    int? bakedAt,
  }) => GroupedWallpaperState(
        version: version ?? this.version,
        generation: generation ?? this.generation,
        status: status ?? this.status,
        groupId: groupId ?? this.groupId,
        groupNumber: groupNumber ?? this.groupNumber,
        groupName: groupName ?? this.groupName,
        count: count ?? this.count,
        current: current ?? this.current,
        next: next ?? this.next,
        next2: next2 ?? this.next2,
        slots: slots ?? this.slots,
        recent: recent ?? this.recent,
        cursor: cursor ?? this.cursor,
        newestEntryId: newestEntryId ?? this.newestEntryId,
        ordering: ordering ?? this.ordering,
        gestures: gestures ?? this.gestures,
        paused: paused ?? this.paused,
        notification: notification ?? this.notification,
        bakedAt: bakedAt ?? this.bakedAt,
      );

  /// [recent] with the current photo moved to the front, de-duplicated and
  /// capped at [maxRecent].
  ///
  /// Only the metadata is kept: the slot's photo path is reused by a later bake
  /// and would point at another image.
  static List<GroupedWallpaperRecentEntry> promoteRecent(
    List<GroupedWallpaperRecentEntry> recent,
    GroupedWallpaperSlot? slot, {
    String groupId = '',
  }) {
    if (slot == null) return recent;
    final metadata = GroupedWallpaperRecentEntry(entryId: slot.entryId, uri: slot.uri, title: slot.title, groupId: groupId);
    return [
      metadata,
      ...recent.where((existing) => existing.entryId != metadata.entryId),
    ].take(maxRecent).toList(growable: false);
  }

  Map<String, Object?> toJsonMap() => {
        'version': version,
        'generation': generation,
        'status': status.name,
        'groupId': groupId,
        'groupNumber': groupNumber,
        'groupName': groupName,
        'count': count,
        'current': current,
        'next': next,
        'next2': next2,
        'slots': slots.map((slot) => slot.toJsonMap()).toList(),
        'recent': recent.map((entry) => entry.toJsonMap()).toList(),
        'cursor': cursor,
        'newestEntryId': newestEntryId,
        'ordering': ordering.name,
        'gestures': gestures.toJsonMap(),
        'paused': paused,
        'notification': notification,
        'bakedAt': bakedAt,
      };

  static GroupedWallpaperState? tryFromJsonMap(Map<String, Object?> json) {
    final version = _int(json['version']);
    final status = GroupedWallpaperStatus.tryParse(json['status']);
    if (status == null) return null;
    return switch (version) {
      1 => _fromV1(json, status),
      2 || 3 || 4 => _fromQueued(json, status),
      _ => null,
    };
  }

  /// v1 stored one baked photo (`current.png`) and no queue.
  static GroupedWallpaperState? _fromV1(Map<String, Object?> json, GroupedWallpaperStatus status) {
    final entryId = _int(json['entryId']);
    final photo = _string(json['photo']);
    final drawsFrame = status == GroupedWallpaperStatus.ready || status.keepsFrame;
    final hasFrame = drawsFrame && photo.isNotEmpty && entryId != null;
    return GroupedWallpaperState(
      generation: _int(json['generation']) ?? 0,
      status: status == GroupedWallpaperStatus.ready && !hasFrame ? GroupedWallpaperStatus.unavailable : status,
      groupId: _string(json['groupId']),
      groupNumber: _int(json['groupNumber']) ?? 0,
      groupName: _string(json['groupName']),
      count: _int(json['count']) ?? 0,
      current: hasFrame ? 0 : -1,
      slots: hasFrame
          ? [
              GroupedWallpaperSlot(
                id: 0,
                entryId: entryId,
                uri: '',
                title: _string(json['entryTitle']),
                photo: photo,
                width: _int(json['width']) ?? 0,
                height: _int(json['height']) ?? 0,
              ),
            ]
          : const [],
      bakedAt: _int(json['bakedAt']) ?? 0,
    );
  }

  static GroupedWallpaperState _fromQueued(Map<String, Object?> json, GroupedWallpaperStatus status) {
    final slots = <GroupedWallpaperSlot>[];
    final seenIds = <int>{};
    final rawSlots = json['slots'];
    if (rawSlots is List) {
      for (final rawSlot in rawSlots) {
        if (rawSlot is! Map) continue;
        final slot = GroupedWallpaperSlot.tryFromJsonMap(rawSlot.map((key, value) => MapEntry(key.toString(), value)));
        if (slot != null && seenIds.add(slot.id)) slots.add(slot);
      }
    }
    final recent = <GroupedWallpaperRecentEntry>[];
    final seenRecent = <int>{};
    final rawRecent = json['recent'];
    if (rawRecent is List) {
      for (final rawEntry in rawRecent) {
        if (rawEntry is! Map || recent.length >= maxRecent) continue;
        final entry = GroupedWallpaperRecentEntry.tryFromJsonMap(rawEntry.map((key, value) => MapEntry(key.toString(), value)));
        if (entry != null && seenRecent.add(entry.entryId)) recent.add(entry);
      }
    }
    int readSlotId(Object? value) {
      final id = _int(value);
      return id != null && id >= 0 ? id : -1;
    }

    final state = GroupedWallpaperState(
      generation: _int(json['generation']) ?? 0,
      status: status,
      groupId: _string(json['groupId']),
      groupNumber: _int(json['groupNumber']) ?? 0,
      groupName: _string(json['groupName']),
      count: _int(json['count']) ?? 0,
      current: readSlotId(json['current']),
      next: readSlotId(json['next']),
      next2: readSlotId(json['next2']),
      slots: List.unmodifiable(slots),
      recent: List.unmodifiable(recent),
      cursor: _int(json['cursor']) ?? 0,
      newestEntryId: _int(json['newestEntryId']) ?? 0,
      ordering: GroupedWallpaperOrdering.tryParse(json['ordering']),
      gestures: GroupedWallpaperGestures.fromJsonMap(_map(json['gestures']) ?? const {}),
      paused: json['paused'] == true,
      // Files written before the setting existed kept the bar on, which is what
      // those builds did.
      notification: json['notification'] != false,
      bakedAt: _int(json['bakedAt']) ?? 0,
    );
    // `ready` without a frame is a contradiction: show the placeholder instead
    // of claiming an image that is not there. `locked` and `disabled`
    // legitimately keep no frame when nothing was ever baked.
    if (state.status == GroupedWallpaperStatus.ready && !state.hasPhoto) {
      return state.copyWith(status: GroupedWallpaperStatus.unavailable);
    }
    return state;
  }

  static int? _int(Object? value) => value is int ? value : (value is num ? value.toInt() : null);

  static Map<String, Object?>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _string(Object? value) => value is String ? value : '';

  @override
  List<Object?> get props => [version, generation, status, groupId, groupNumber, groupName, count, current, next, next2, slots, recent, cursor, newestEntryId, ordering, gestures, paused, notification, bakedAt];
}

/// Native-owned `runtime.json`.
///
/// The renderer may promote a slot before Dart has baked the freed one, so it
/// records what it is showing. A generation mismatch means the file predates the
/// latest [GroupedWallpaperState] and must be ignored.
@immutable
class GroupedWallpaperRuntime extends Equatable {
  final int generation;
  final int current;
  final int next;

  /// Whether the renderer promoted a slot and needs the freed one baked again.
  final bool refillRequested;

  const new({
    required this.generation,
    required this.current,
    required this.next,
    this.refillRequested = false,
  });

  static const empty = GroupedWallpaperRuntime(generation: -1, current: -1, next: -1);

  bool get hasCurrent => current >= 0;

  bool matches(GroupedWallpaperState state) => generation == state.generation;

  Map<String, Object?> toJsonMap() => {
        'generation': generation,
        'current': current,
        'next': next,
        'refillRequested': refillRequested,
      };

  static GroupedWallpaperRuntime? tryFromJsonMap(Map<String, Object?> json) {
    final generation = GroupedWallpaperState._int(json['generation']);
    if (generation == null) return null;
    return GroupedWallpaperRuntime(
      generation: generation,
      current: GroupedWallpaperState._int(json['current']) ?? -1,
      next: GroupedWallpaperState._int(json['next']) ?? -1,
      refillRequested: json['refillRequested'] == true,
    );
  }

  @override
  List<Object?> get props => [generation, current, next, refillRequested];
}
