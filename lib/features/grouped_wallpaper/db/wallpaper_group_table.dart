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

  @override
  Set<Column> get primaryKey => {id};
}
