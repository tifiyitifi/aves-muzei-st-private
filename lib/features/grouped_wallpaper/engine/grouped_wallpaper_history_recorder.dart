import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/grouped_wallpaper_history_store.dart';
import 'package:aves/services/common/services.dart';

/// Writes one row of the grouped wallpaper's usage history.
///
/// The engine depends on this interface instead of the database, so a test can
/// assert what was recorded without opening one, and a recording failure never
/// reaches the bake pipeline.
abstract interface class GroupedWallpaperHistoryRecorder {
  Future<void> record({
    required int entryId,
    required String groupId,
    required String groupName,
    required int groupNumber,
    required int usedAt,
    required int limit,
  });
}

/// The default recorder: one row in the app database.
class DbGroupedWallpaperHistoryRecorder implements GroupedWallpaperHistoryRecorder {
  final AppDatabaseProvider? provider;

  new({this.provider});

  @override
  Future<void> record({
    required int entryId,
    required String groupId,
    required String groupName,
    required int groupNumber,
    required int usedAt,
    required int limit,
  }) async {
    final db = await (provider ?? getIt<AppDatabaseProvider>()).open();
    await GroupedWallpaperHistoryStore(db).record(
      entryId: entryId,
      groupId: groupId,
      groupName: groupName,
      groupNumber: groupNumber,
      usedAt: usedAt,
      limit: limit,
    );
  }
}
