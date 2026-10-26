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

/// Rule id owned by a wallpaper group.
///
/// Rule ids are global (one table), so the same bundled candidate gets a
/// different id per group: seeding the same restrictions into two groups must
/// not collide. The prefix keeps the id readable in a database dump.
String wallpaperGroupRuleId(String groupId, String definitionId) => '$groupId.rule.$definitionId';

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
  final bool enabled;

  /// The group the actual wallpaper uses. At most one group is current; when no
  /// group is current the wallpaper falls back to [none].
  final bool current;
  final int createdAt;
  final int updatedAt;

  const new({
    required this.id,
    this.number = 0,
    this.name = '',
    this.enabled = true,
    this.current = false,
    this.createdAt = 0,
    this.updatedAt = 0,
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
    bool? enabled,
    bool? current,
    int? updatedAt,
  }) {
    return WallpaperGroup(
      id: id,
      number: number ?? this.number,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      current: current ?? this.current,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, number, name, enabled, current, createdAt, updatedAt];
}
