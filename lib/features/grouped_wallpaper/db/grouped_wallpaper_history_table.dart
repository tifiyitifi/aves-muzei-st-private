import 'package:drift/drift.dart';

/// One photo the grouped wallpaper has shown.
///
/// It is a history, not a queue: the baked slot files are recycled, so the row
/// only keeps the entry id and enough of the group to label the row after the
/// group was renamed or deleted.
///
/// The unique key is `(entryId, groupId)`: the same photo shown again updates its
/// `usedAt` instead of adding a row, while the same photo in another group is a
/// different wallpaper and keeps its own row.
class GroupedWallpaperHistoryRows extends Table {
  @override
  String get tableName => 'grouped_wallpaper_history';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get entryId => integer().named('entryId')();

  TextColumn get groupId => text().named('groupId')();

  /// The group's stored name (`@arbKey` or user text), localized on display.
  TextColumn get groupName => text().named('groupName').withDefault(const Constant(''))();

  /// The group number at the time, for a group that has no name of its own.
  IntColumn get groupNumber => integer().named('groupNumber').withDefault(const Constant(0))();

  /// When the photo was put on screen, in milliseconds since the epoch.
  IntColumn get usedAt => integer().named('usedAt')();

  @override
  List<String> get customConstraints => const ['UNIQUE (entryId, groupId)'];
}
