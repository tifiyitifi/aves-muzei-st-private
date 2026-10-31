import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_limit.dart';
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

/// One photo "previous" can step back to.
///
/// Only the id is kept: a slot is recycled, and the entry is read from the
/// group's range again when it is shown, so a deleted photo never blocks the
/// walk. The list is capped by the usage history limit.
@immutable
class GroupedWallpaperRewindEntry extends Equatable {
  final int entryId;

  const new({required this.entryId});

  Map<String, Object?> toJsonMap() => {'entryId': entryId};

  static GroupedWallpaperRewindEntry? tryFromJsonMap(Map<String, Object?> json) {
    final entryId = GroupedWallpaperSlot._slotInt(json['entryId']);
    if (entryId == null || entryId <= 0) return null;
    return GroupedWallpaperRewindEntry(entryId: entryId);
  }

  @override
  List<Object?> get props => [entryId];
}

/// One group of the rotation, as `state.json` carries it.
///
/// The notification switches groups natively, so it needs the ordered rotation
/// and the display names without asking the app; [name] is already localized
/// text, not the stored `@arbKey`, because the native side cannot resolve one.
@immutable
class GroupedWallpaperGroup extends Equatable {
  final String id;
  final int number;
  final String name;

  const new({
    required this.id,
    this.number = 0,
    this.name = '',
  });

  Map<String, Object?> toJsonMap() => {
        'id': id,
        'number': number,
        'name': name,
      };

  static GroupedWallpaperGroup? tryFromJsonMap(Map<String, Object?> json) {
    final id = GroupedWallpaperSlot._slotString(json['id']);
    if (id.isEmpty) return null;
    return GroupedWallpaperGroup(
      id: id,
      number: GroupedWallpaperSlot._slotInt(json['number']) ?? 0,
      name: GroupedWallpaperSlot._slotString(json['name']),
    );
  }

  @override
  List<Object?> get props => [id, number, name];
}

/// Dart-owned `state.json` of the grouped wallpaper.
///
/// This is the contract between the Flutter engine and the native renderer: only
/// Dart writes it, and the native side writes [GroupedWallpaperRuntime] instead.
/// It also carries what the notification shows (group number, group name, entry,
/// count, status), so the service never has to ask the app for text it cannot
/// localize itself.
///
/// [previous] → [current] → [next] is the navigation queue. Both neighbours are
/// baked, so the renderer can step through the usage history in either direction
/// without waiting for a bake: a wallpaper tap promotes [next], the bar's
/// "previous" promotes [previous], and Dart refills what was left behind.
///
/// Parsing is deliberately tolerant: a state file written by another version, or
/// truncated by a crash, must leave the wallpaper on its placeholder instead of
/// crashing the service.
@immutable
class GroupedWallpaperState extends Equatable {
  /// v2 added the slot queue; v3 added the ordering metadata ([recent],
  /// [cursor], [newestEntryId]); v4 added the group id of a recent entry; v5
  /// added the rewind stack ([rewind], [rewindCursor]) and [navigated]; v6 made
  /// both neighbours explicit ([previous], [next]) so the native side can step
  /// through the records without baking. Older files are read with those at
  /// their defaults, so an upgrade never loses the frame on screen.
  /// [notification], the [surfaceWidth] / [surfaceHeight] layout,
  /// [scrollEffect], [historyLimit], [switchLocked], [switchLockedGroupId] and
  /// [groups] were added afterwards without a version bump: a file without them
  /// means "on" for the bar and "unknown" for the layout, which re-bakes once.
  /// A v4 file seeds [rewind] from [recent], so "previous" works right after the
  /// update.
  static const int currentVersion = 6;

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

  /// The slot on screen.
  final int current;

  /// The slot of the older history record, or `-1` when the walk reached its end.
  final int previous;

  /// The slot of the newer history record, or the freshly picked photo when the
  /// cursor is at the newest record. `-1` when the group cannot move forward.
  final int next;

  /// The baked neighbours ([previous], [current], [next]).
  ///
  /// Both directions are queued so the native side can step through the usage
  /// history without waiting for a bake: the bar and a wallpaper gesture only
  /// change which slot is drawn, and Dart refills the neighbour left behind.
  final List<GroupedWallpaperSlot> slots;

  /// Photos the wallpaper has shown, newest first.
  final List<GroupedWallpaperRecentEntry> recent;

  /// Photos "previous" can walk back through, newest first.
  ///
  /// It is the usage history as the wallpaper navigates it: a new photo goes to
  /// the front and resets [rewindCursor], while "previous"/"next" only move the
  /// cursor. It is capped by [historyLimit], so the walk never goes further back
  /// than the records the user keeps.
  final List<GroupedWallpaperRewindEntry> rewind;

  /// Position of the current photo in [rewind]; `0` is the newest.
  final int rewindCursor;

  /// Whether this state was written by an explicit history step.
  ///
  /// The native renderer keeps the slot on screen when a newer state still
  /// queues it after `current` (a promotion it made itself). A previous/next
  /// bake looks the same in the queue, so [navigated] tells the renderer to
  /// honor the new `current` instead of keeping the old frame.
  final bool navigated;

  /// Whether this state was parsed from a file written before the rewind stack.
  ///
  /// Not serialized: a write always produces a current state. It only tells the
  /// engine to rewrite `state.json` once, so the native bar sees `canPrevious`.
  final bool needsUpgrade;

  /// Position of the next in-order pick within the group.
  final int cursor;

  /// Highest entry id shown, so photos added afterwards are served first.
  final int newestEntryId;

  /// Ordering the queue was baked with, for continuity across restarts.
  final GroupedWallpaperOrdering ordering;

  /// Gestures the renderer acts on without asking Dart.
  final GroupedWallpaperGestures gestures;

  /// Whether the user lets the wallpaper show its notification bar.
  ///
  /// It travels with the state because the service owns the bar: with this off it
  /// posts nothing and never promotes itself to a foreground service.
  final bool notification;

  /// The wallpaper surface this frame was baked for.
  ///
  /// The launcher changes it on rotation and when it updates its dimension hints;
  /// a frame baked for another surface would be stretched or cropped, so the
  /// engine re-bakes once when it differs. `0` means "written before this was
  /// recorded", which also re-bakes once.
  final int surfaceWidth;
  final int surfaceHeight;

  /// Whether the frames were baked with the home-screen scroll effect.
  ///
  /// It changes the width of every frame, so a mismatch with the current switch
  /// re-bakes once, exactly like a surface change.
  final bool scrollEffect;

  /// How many photos the usage history keeps; `0` turns recording off.
  ///
  /// It travels with the state because the notification owns the "previous"
  /// button: with recording off the bar greys it out instead of asking the app.
  final int historyLimit;

  /// Whether the group-switch lock is on, so the bar greys its group buttons.
  ///
  /// It travels with the state because the notification is built natively from
  /// `state.json`: without the flag the bar would offer a switch the Dart side
  /// must refuse. The Dart lock service refreshes it when the lock changes, and
  /// every bake records the current value.
  final bool switchLocked;

  /// The group the lock was set on, or blank when nothing is locked.
  ///
  /// The bar compares it with the group on screen: a lock set on another group
  /// still protects switching, but the lock button then offers to lock the group
  /// actually showing instead of pretending it already is.
  final String switchLockedGroupId;

  /// The rotation the bar cycles, in display order.
  ///
  /// The notification switches groups natively so a tap changes the bar at once;
  /// it needs the enabled groups and their display names to do that without
  /// waking the app.
  final List<GroupedWallpaperGroup> groups;

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
    this.previous = -1,
    this.next = -1,
    this.slots = const [],
    this.recent = const [],
    this.rewind = const [],
    this.rewindCursor = 0,
    this.navigated = false,
    this.needsUpgrade = false,
    this.cursor = 0,
    this.newestEntryId = 0,
    this.ordering = GroupedWallpaperOrdering.defaultOrdering,
    this.gestures = const GroupedWallpaperGestures(),
    this.notification = true,
    this.surfaceWidth = 0,
    this.surfaceHeight = 0,
    this.scrollEffect = false,
    this.historyLimit = GroupedWallpaperHistoryLimit.defaultLimit,
    this.switchLocked = false,
    this.switchLockedGroupId = '',
    this.groups = const [],
    this.bakedAt = 0,
  });

  GroupedWallpaperSlot? slotById(int id) {
    for (final slot in slots) {
      if (slot.id == id) return slot;
    }
    return null;
  }

  GroupedWallpaperSlot? get currentSlot => slotById(current);

  GroupedWallpaperSlot? get previousSlot => slotById(previous);

  GroupedWallpaperSlot? get nextSlot => slotById(next);

  /// Whether the state points at a baked frame, whatever the status: a locked or
  /// turned-off group keeps showing the photo it stopped on.
  bool get hasPhoto => currentSlot != null;

  /// Whether "previous" would change the frame.
  ///
  /// It mirrors what the native side can do without Dart: the older neighbour
  /// must be baked and queued. A locked range still navigates (the lock protects
  /// editing, not the photos), while a turned-off or unavailable wallpaper has
  /// nothing to show.
  bool get canGoPrevious =>
      hasPhoto &&
      historyLimit > 0 &&
      (status == GroupedWallpaperStatus.ready || status == GroupedWallpaperStatus.locked) &&
      previous >= 0;

  /// Whether "next" would change the frame.
  bool get canGoNext =>
      hasPhoto &&
      (status == GroupedWallpaperStatus.ready || status == GroupedWallpaperStatus.locked) &&
      next >= 0;

  /// How many slots are queued, current included.
  int get queueLength => [previous, current, next].where((id) => id >= 0).toSet().length;

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
    int? previous,
    int? next,
    List<GroupedWallpaperSlot>? slots,
    List<GroupedWallpaperRecentEntry>? recent,
    List<GroupedWallpaperRewindEntry>? rewind,
    int? rewindCursor,
    bool? navigated,
    bool? needsUpgrade,
    int? cursor,
    int? newestEntryId,
    GroupedWallpaperOrdering? ordering,
    GroupedWallpaperGestures? gestures,
    bool? notification,
    int? surfaceWidth,
    int? surfaceHeight,
    bool? scrollEffect,
    int? historyLimit,
    bool? switchLocked,
    String? switchLockedGroupId,
    List<GroupedWallpaperGroup>? groups,
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
        previous: previous ?? this.previous,
        next: next ?? this.next,
        slots: slots ?? this.slots,
        recent: recent ?? this.recent,
        rewind: rewind ?? this.rewind,
        rewindCursor: rewindCursor ?? this.rewindCursor,
        navigated: navigated ?? this.navigated,
        needsUpgrade: needsUpgrade ?? this.needsUpgrade,
        cursor: cursor ?? this.cursor,
        newestEntryId: newestEntryId ?? this.newestEntryId,
        ordering: ordering ?? this.ordering,
        gestures: gestures ?? this.gestures,
        notification: notification ?? this.notification,
        surfaceWidth: surfaceWidth ?? this.surfaceWidth,
        surfaceHeight: surfaceHeight ?? this.surfaceHeight,
        scrollEffect: scrollEffect ?? this.scrollEffect,
        historyLimit: historyLimit ?? this.historyLimit,
        switchLocked: switchLocked ?? this.switchLocked,
        switchLockedGroupId: switchLockedGroupId ?? this.switchLockedGroupId,
        groups: groups ?? this.groups,
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
        'previous': previous,
        'next': next,
        'slots': slots.map((slot) => slot.toJsonMap()).toList(),
        'recent': recent.map((entry) => entry.toJsonMap()).toList(),
        'rewind': rewind.map((entry) => entry.toJsonMap()).toList(),
        'rewindCursor': rewindCursor,
        'canPrevious': canGoPrevious,
        'navigated': navigated,
        'cursor': cursor,
        'newestEntryId': newestEntryId,
        'ordering': ordering.name,
        'gestures': gestures.toJsonMap(),
        'notification': notification,
        'surfaceWidth': surfaceWidth,
        'surfaceHeight': surfaceHeight,
        'scrollEffect': scrollEffect,
        'historyLimit': historyLimit,
        'switchLocked': switchLocked,
        'switchLockedGroupId': switchLockedGroupId,
        'groups': groups.map((group) => group.toJsonMap()).toList(),
        'bakedAt': bakedAt,
      };

  static GroupedWallpaperState? tryFromJsonMap(Map<String, Object?> json) {
    final version = _int(json['version']);
    final status = GroupedWallpaperStatus.tryParse(json['status']);
    if (status == null) return null;
    return switch (version) {
      1 => _fromV1(json, status),
      2 || 3 || 4 => _fromQueued(json, status, needsUpgrade: true),
      5 => _fromQueued(json, status, needsUpgrade: true),
      6 => _fromQueued(json, status, needsUpgrade: false),
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
      needsUpgrade: true,
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

  static GroupedWallpaperState _fromQueued(Map<String, Object?> json, GroupedWallpaperStatus status, {required bool needsUpgrade}) {
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

    final groups = <GroupedWallpaperGroup>[];
    final seenGroups = <String>{};
    final rawGroups = json['groups'];
    if (rawGroups is List) {
      for (final rawGroup in rawGroups) {
        if (rawGroup is! Map) continue;
        final group = GroupedWallpaperGroup.tryFromJsonMap(rawGroup.map((key, value) => MapEntry(key.toString(), value)));
        if (group != null && seenGroups.add(group.id)) groups.add(group);
      }
    }

    // The limit bounds the walk, so it is read before the stack.
    final historyLimit = GroupedWallpaperHistoryLimit.sanitize(_int(json['historyLimit']) ?? GroupedWallpaperHistoryLimit.defaultLimit);
    final groupId = _string(json['groupId']);
    final rewind = <GroupedWallpaperRewindEntry>[];
    final seenRewind = <int>{};
    final hasRewind = json.containsKey('rewind');
    final rawRewind = json['rewind'];
    if (rawRewind is List) {
      for (final rawEntry in rawRewind) {
        if (rawEntry is! Map || rewind.length >= historyLimit) continue;
        final entry = GroupedWallpaperRewindEntry.tryFromJsonMap(rawEntry.map((key, value) => MapEntry(key.toString(), value)));
        if (entry != null && seenRewind.add(entry.entryId)) rewind.add(entry);
      }
    }
    if (!hasRewind && historyLimit > 0) {
      // A v4 file predates the stack: its recent list is already newest first,
      // so "previous" works on the first tap after the update.
      for (final entry in recent) {
        if (rewind.length >= historyLimit) break;
        if (entry.groupId.isNotEmpty && entry.groupId != groupId) continue;
        if (seenRewind.add(entry.entryId)) rewind.add(GroupedWallpaperRewindEntry(entryId: entry.entryId));
      }
    }
    final rewindCursor = (_int(json['rewindCursor']) ?? 0).clamp(0, rewind.isEmpty ? 0 : rewind.length - 1);

    final state = GroupedWallpaperState(
      needsUpgrade: needsUpgrade,
      generation: _int(json['generation']) ?? 0,
      status: status,
      groupId: groupId,
      groupNumber: _int(json['groupNumber']) ?? 0,
      groupName: _string(json['groupName']),
      count: _int(json['count']) ?? 0,
      current: readSlotId(json['current']),
      previous: readSlotId(json['previous']),
      next: readSlotId(json['next']),
      slots: List.unmodifiable(slots),
      recent: List.unmodifiable(recent),
      rewind: List.unmodifiable(rewind),
      rewindCursor: rewindCursor,
      navigated: json['navigated'] == true,
      cursor: _int(json['cursor']) ?? 0,
      newestEntryId: _int(json['newestEntryId']) ?? 0,
      ordering: GroupedWallpaperOrdering.tryParse(json['ordering']),
      gestures: GroupedWallpaperGestures.fromJsonMap(_map(json['gestures']) ?? const {}),
      // Files written before the setting existed kept the bar on, which is what
      // those builds did.
      notification: json['notification'] != false,
      // Absent means "unknown": the next run bakes once for the real layout.
      surfaceWidth: _int(json['surfaceWidth']) ?? 0,
      surfaceHeight: _int(json['surfaceHeight']) ?? 0,
      scrollEffect: json['scrollEffect'] == true,
      // Files written before the limit existed recorded everything, which is what
      // the store's default still does.
      historyLimit: historyLimit,
      switchLocked: json['switchLocked'] == true,
      switchLockedGroupId: _string(json['switchLockedGroupId']),
      groups: List.unmodifiable(groups),
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
  List<Object?> get props => [version, generation, status, groupId, groupNumber, groupName, count, current, previous, next, slots, recent, rewind, rewindCursor, navigated, needsUpgrade, cursor, newestEntryId, ordering, gestures, notification, surfaceWidth, surfaceHeight, scrollEffect, historyLimit, switchLocked, switchLockedGroupId, groups, bakedAt];
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
