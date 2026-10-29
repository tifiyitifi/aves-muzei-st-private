import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Id of the virtual 「no wallpaper group effect」 entry.
///
/// Group 0 is a constant, not a row: it owns no visible range, never changes the
/// wallpaper and never joins the notification rotation, so there is nothing to
/// persist or migrate for it.
const String wallpaperGroupNoneId = 'none';

/// Visible-range id owned by a wallpaper group.
///
/// Derived from the group id instead of stored on the group row, so a group and
/// its range can never drift apart: one group owns exactly one `wallpaper`-scope
/// range, and renumbering the groups never moves a range.
String wallpaperGroupRangeId(String groupId) => '$groupId.range';

/// One wallpaper group: the unit that owns a visible range.
///
/// [number] is derived from the stored position (`1..n`), never edited by hand.
/// [name] is an ARB key prefixed with `@` while the group keeps its built-in
/// name, so it follows the app language; as soon as the user renames it the
/// stored value is plain text and no seeding pass may overwrite it.
@immutable
class WallpaperGroup extends Equatable {
  final String id;
  final int number;
  final String name;

  /// Free-form note shown under the name on the group cards. New groups start
  /// with the creation date, and a bundled group starts empty.
  final String description;
  final bool enabled;

  /// The group the actual wallpaper uses. At most one group is current; when no
  /// group is current the wallpaper falls back to [none].
  final bool current;
  final int createdAt;
  final int updatedAt;

  /// Home and lock effects applied when this group's photos are baked.
  ///
  /// Effects belong to the group, not the app: a private group can be blurred
  /// while a public one stays sharp. The values are Muzei's, so the effects page
  /// and the baker share one scale.
  final WallpaperEffectsConfig effects;

  /// How often this group moves to its next photo.
  ///
  /// [WallpaperInterval.never] is the default, like Muzei: a group keeps its
  /// photo until the user, the notification or a tap asks for another one.
  final WallpaperInterval interval;

  /// How the next photo is chosen within this group.
  final GroupedWallpaperOrdering ordering;

  const new({
    required this.id,
    this.number = 0,
    this.name = '',
    this.description = '',
    this.enabled = true,
    this.current = false,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.effects = const WallpaperEffectsConfig(),
    this.interval = WallpaperInterval.never,
    this.ordering = GroupedWallpaperOrdering.defaultOrdering,
  });

  /// The fixed group 0 entry: no row, no range, no wallpaper change.
  static const none = WallpaperGroup(
    id: wallpaperGroupNoneId,
    number: 0,
    name: '@wallpaperGroupNone',
    enabled: false,
    current: true,
  );

  bool get isNone => id == wallpaperGroupNoneId;

  /// Whether the name is still the bundled, localized one.
  bool get hasBundledName => name.isEmpty || name.startsWith('@');

  WallpaperGroup copyWith({
    int? number,
    String? name,
    String? description,
    bool? enabled,
    bool? current,
    int? updatedAt,
    WallpaperEffectsConfig? effects,
    WallpaperInterval? interval,
    GroupedWallpaperOrdering? ordering,
  }) {
    return WallpaperGroup(
      id: id,
      number: number ?? this.number,
      name: name ?? this.name,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      current: current ?? this.current,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      effects: effects ?? this.effects,
      interval: interval ?? this.interval,
      ordering: ordering ?? this.ordering,
    );
  }

  @override
  List<Object?> get props => [id, number, name, description, enabled, current, createdAt, updatedAt, effects, interval, ordering];
}
