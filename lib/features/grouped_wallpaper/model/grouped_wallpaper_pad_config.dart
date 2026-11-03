import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// One action the view page's control pad can carry.
///
/// The enum is the stored identity: slots are saved by [name], so renaming a
/// member would silently empty a user's pad. Add new members at the end.
enum GroupedWallpaperPadAction {
  previousPhoto,
  nextPhoto,
  more,
  nextGroup,
  previousGroup,
  delete,
  openGroups,
  openInGallery,
  viewWholeGroup,
  share,
  history,
  autoAdvance,
  effects,
  gestures,
  switchSurface,
  toggleNotification,
  disableWallpaper,
  toggleLock,
  about;

  static GroupedWallpaperPadAction? tryParse(Object? value) {
    for (final action in values) {
      if (action.name == value) return action;
    }
    return null;
  }
}

/// The columns and rows the pad currently draws.
///
/// Square keeps the historical 3x3 box, including its empty cells. Adaptive
/// shapes are derived from how many actions are actually assigned, and only the
/// view page uses them; the editor always shows the fixed 9 slots.
@immutable
class GroupedWallpaperPadShape extends Equatable {
  final int columns;
  final int rows;

  const new(this.columns, this.rows);

  int get capacity => columns * rows;

  @override
  List<Object?> get props => [columns, rows];
}

/// The view page pad's 9 fixed slots plus its two presentation switches.
///
/// Positions are fixed rather than an ordered list, because the historical
/// staircase puts the delete button in the third row while leaving the middle
/// row's last cell empty. Compacting the slots here would move it.
///
/// The two switches are independent:
/// - [fitToActions] lets the view page shrink the box to the assigned actions;
///   the editor still shows all 9 slots so the user can place an action anywhere.
/// - [bottomBar] replaces the floating pad with one row in the artwork panel when
///   at most three actions are assigned. It is forced off as soon as a fourth
///   action exists, so it cannot silently reappear after a later removal.
@immutable
class GroupedWallpaperPadConfig with Equatable {
  static const int slotCount = 9;
  static const int columns = 3;
  static const int rows = 3;

  /// The slot the historical menu button occupies.
  static const int moreSlot = 2;

  /// The layout before the pad became configurable: previous/next/more, then
  /// group +1/-1, then delete, with the two middle-row gaps preserved.
  static const List<GroupedWallpaperPadAction?> defaultSlots = [
    GroupedWallpaperPadAction.previousPhoto,
    GroupedWallpaperPadAction.nextPhoto,
    GroupedWallpaperPadAction.more,
    GroupedWallpaperPadAction.nextGroup,
    GroupedWallpaperPadAction.previousGroup,
    null,
    GroupedWallpaperPadAction.delete,
    null,
    null,
  ];

  static const defaultConfig = GroupedWallpaperPadConfig(
    slots: defaultSlots,
    fitToActions: false,
    bottomBar: false,
  );

  /// Nine fixed positions; a null slot is unassigned.
  final List<GroupedWallpaperPadAction?> slots;

  /// Whether the live pad shrinks to the assigned actions.
  final bool fitToActions;

  /// Whether the live view shows one row in the artwork panel instead of the pad.
  final bool bottomBar;

  /// The raw constructor: callers that accept user input use [safe] instead.
  const new({
    required this.slots,
    this.fitToActions = false,
    this.bottomBar = false,
  });

  /// Builds a valid configuration, repairing anything a hand-edited row or an
  /// older build could contain.
  factory safe({
    List<GroupedWallpaperPadAction?>? slots,
    bool fitToActions = false,
    bool bottomBar = false,
  }) {
    final sanitized = sanitizeSlots(slots ?? defaultSlots);
    return GroupedWallpaperPadConfig(
      slots: sanitized,
      fitToActions: fitToActions,
      // A bottom bar is a row of at most three buttons; a fourth action would
      // silently drop one, so the mode simply turns itself off.
      bottomBar: bottomBar && actionCountOf(sanitized) <= 3,
    );
  }

  /// The assigned actions, in slot order: what the adaptive shape lays out and
  /// what a bottom bar shows.
  List<GroupedWallpaperPadAction> get actions => [
    for (final action in slots) ?action,
  ];

  int get actionCount => actions.length;

  /// Whether the bottom-bar switch can be offered at all.
  bool get canUseBottomBar => actionCount <= 3;

  /// Whether the live view should use the single row instead of the pad.
  bool get usesBottomBar => bottomBar && canUseBottomBar;

  /// The shape to draw for the device's current orientation.
  GroupedWallpaperPadShape shapeFor({required bool portrait}) {
    if (!fitToActions) return const GroupedWallpaperPadShape(columns, rows);
    return switch (actionCount) {
      <= 1 => const GroupedWallpaperPadShape(1, 1),
      2 => portrait ? const GroupedWallpaperPadShape(1, 2) : const GroupedWallpaperPadShape(2, 1),
      <= 4 => const GroupedWallpaperPadShape(2, 2),
      <= 6 => portrait ? const GroupedWallpaperPadShape(2, 3) : const GroupedWallpaperPadShape(3, 2),
      _ => const GroupedWallpaperPadShape(3, 3),
    };
  }

  /// The cells to draw for [shape].
  ///
  /// Square mode keeps every fixed slot, gaps included. Adaptive mode compacts
  /// the assigned actions so a gap in the middle of the 9 slots does not leave a
  /// hole in a 2x2 box; trailing cells the shape does not need are null.
  List<GroupedWallpaperPadAction?> cellsFor(GroupedWallpaperPadShape shape) {
    final source = fitToActions ? actions : slots;
    return [
      for (var i = 0; i < shape.capacity; i++) i < source.length ? source[i] : null,
    ];
  }

  GroupedWallpaperPadConfig copyWith({
    List<GroupedWallpaperPadAction?>? slots,
    bool? fitToActions,
    bool? bottomBar,
  }) => GroupedWallpaperPadConfig.safe(
    slots: slots ?? this.slots,
    fitToActions: fitToActions ?? this.fitToActions,
    bottomBar: bottomBar ?? this.bottomBar,
  );

  /// [this] with the action at [index] replaced (or cleared).
  ///
  /// The menu action cannot be cleared here; the editor prevents it and this
  /// guard keeps a programmatic call from leaving a pad without its menu.
  GroupedWallpaperPadConfig withSlot(int index, GroupedWallpaperPadAction? action) {
    if (index < 0 || index >= slotCount) return this;
    if (action == null && slots[index] == GroupedWallpaperPadAction.more) return this;
    final next = [...slots];
    next[index] = action;
    return copyWith(slots: next);
  }

  /// The first empty slot, or -1 when every cell is assigned.
  int get firstEmptySlot => slots.indexOf(null);

  /// Assigns [action] to its first free slot, ignoring duplicates.
  GroupedWallpaperPadConfig withActionAdded(GroupedWallpaperPadAction action) {
    if (slots.contains(action)) return this;
    final index = firstEmptySlot;
    if (index < 0) return this;
    return withSlot(index, action);
  }

  Map<String, Object?> toJsonMap() => {
    'slots': [for (final action in slots) action?.name],
    'fitToActions': fitToActions,
    'bottomBar': bottomBar,
  };

  String encode() => jsonEncode(toJsonMap());

  /// Reads a stored configuration; null when the value is not a map at all.
  static GroupedWallpaperPadConfig? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJsonMap(decoded.map((key, value) => MapEntry(key.toString(), value)));
    } catch (_) {
      // A corrupt value must not cost the user their pad.
      return null;
    }
  }

  static GroupedWallpaperPadConfig fromJsonMap(Map<String, Object?> json) {
    final rawSlots = json['slots'];
    final slots = <GroupedWallpaperPadAction?>[];
    if (rawSlots is List) {
      for (final raw in rawSlots) {
        if (slots.length >= slotCount) break;
        slots.add(GroupedWallpaperPadAction.tryParse(raw));
      }
    }
    return GroupedWallpaperPadConfig.safe(
      slots: slots.isEmpty ? defaultSlots : slots,
      fitToActions: json['fitToActions'] == true,
      bottomBar: json['bottomBar'] == true,
    );
  }

  /// Repairs a slot list: 9 entries, no duplicates, and exactly one menu action.
  @visibleForTesting
  static List<GroupedWallpaperPadAction?> sanitizeSlots(List<GroupedWallpaperPadAction?> raw) {
    final result = List<GroupedWallpaperPadAction?>.filled(slotCount, null);
    final seen = <GroupedWallpaperPadAction>{};
    for (var i = 0; i < raw.length && i < slotCount; i++) {
      final action = raw[i];
      if (action == null || !seen.add(action)) continue;
      result[i] = action;
    }
    if (!seen.contains(GroupedWallpaperPadAction.more)) {
      // The historical position first, then any free cell. A full, corrupt list
      // gives up its last action rather than leaving the pad without a menu.
      var target = moreSlot;
      if (result[target] != null) target = result.indexOf(null);
      if (target < 0) target = slotCount - 1;
      result[target] = GroupedWallpaperPadAction.more;
    }
    return List.unmodifiable(result);
  }

  @visibleForTesting
  static int actionCountOf(List<GroupedWallpaperPadAction?> slots) => slots.whereType<GroupedWallpaperPadAction>().length;

  @override
  List<Object?> get props => [slots, fitToActions, bottomBar];
}
