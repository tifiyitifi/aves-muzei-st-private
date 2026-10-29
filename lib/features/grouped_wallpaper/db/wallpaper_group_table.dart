import 'package:drift/drift.dart';

/// One wallpaper group.
///
/// Group 0 is not a row: "no wallpaper group effect" is the absence of a current
/// group, so it needs no number, no name and no visible range.
///
/// `position` is the only stored ordering fact; the display number (`1..n`) is
/// derived from it, so numbers can never have gaps. The enabled segment is
/// implied by `enabled`: enabled groups come first, and the controller
/// normalizes the list after every mutation.
class WallpaperGroupRows extends Table {
  @override
  String get tableName => 'wallpaper_groups';

  TextColumn get id => text()();

  /// `@arbKey` while the group keeps its built-in name, plain user text once
  /// renamed. Never localized in the database.
  TextColumn get name => text().withDefault(const Constant(''))();

  /// Free-form user note shown under the name, e.g. the date the group was
  /// created. Never localized here: it is user text.
  TextColumn get description => text().withDefault(const Constant(''))();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// The group the actual wallpaper uses; at most one row is true.
  BoolColumn get current => boolean().withDefault(const Constant(false))();

  IntColumn get position => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer().named('createdAt')();

  IntColumn get updatedAt => integer().named('updatedAt')();

  /// Home and lock effects as a [WallpaperEffectsConfig] JSON map.
  ///
  /// One column keeps the two surfaces and the link toggle atomic, exactly as the
  /// effects page edits them. The default `{}` reads back as the identity
  /// configuration, so an upgraded group keeps its sharp photos.
  TextColumn get effects => text().withDefault(const Constant('{}'))();

  /// How often this group moves to its next photo, in seconds.
  ///
  /// `0` is Muzei's "off" and the default: a group stays on its photo until the
  /// user, the notification or a tap asks for another one. Storing seconds keeps
  /// the interval choices growable without a migration.
  IntColumn get interval => integer().withDefault(const Constant(0))();

  /// How the next photo is chosen within this group, persisted by enum name.
  ///
  /// The default matches Muzei and the previous global setting: photos added
  /// after the wallpaper moved are shown first, in order, then random.
  TextColumn get ordering => text().withDefault(const Constant('newThenRandom'))();

  @override
  Set<Column> get primaryKey => {id};
}
