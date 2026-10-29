import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/db/grouped_wallpaper_history_store.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_limit.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Persistence of the grouped wallpaper's usage history: the per-photo
/// de-duplication, the prune bound and the limit's "changing it deletes nothing"
/// rule.
void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;
  late GroupedWallpaperHistoryStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = GroupedWallpaperHistoryStore(db);
  });

  tearDown(() => db.close());

  Future<void> record(int entryId, {String groupId = 'group.1', int usedAt = 1, int limit = 200}) => store.record(
        entryId: entryId,
        groupId: groupId,
        groupName: '@wallpaperGroupDefaultDcim',
        groupNumber: 1,
        usedAt: usedAt,
        limit: limit,
      );

  test('records a shown photo with its group snapshot', () async {
    await record(7, usedAt: 100);

    final rows = await store.load();
    expect(rows, hasLength(1));
    expect(rows.single.entryId, 7);
    expect(rows.single.groupId, 'group.1');
    expect(rows.single.groupName, '@wallpaperGroupDefaultDcim');
    expect(rows.single.groupNumber, 1);
    expect(rows.single.usedAt, 100);
    expect(await store.count(), 1);
  });

  test('showing the same photo again only moves it to the front', () async {
    await record(7, usedAt: 100);
    await record(7, usedAt: 300);

    final rows = await store.load();
    expect(rows, hasLength(1));
    expect(rows.single.usedAt, 300);
  });

  test('the same photo in another group is a separate row', () async {
    await record(7, usedAt: 100);
    await record(7, groupId: 'group.2', usedAt: 200);

    expect(await store.count(), 2);
    expect((await store.load()).map((row) => row.groupId), ['group.2', 'group.1']);
  });

  test('a zero limit records nothing', () async {
    await record(7, limit: 0);

    expect(await store.count(), 0);
  });

  test('a write keeps only the newest rows of the limit', () async {
    for (var i = 0; i < 5; i++) {
      await record(i + 1, usedAt: 100 + i, limit: 3);
    }

    final rows = await store.load();
    expect(rows.map((row) => row.entryId), [5, 4, 3]);
  });

  test('load is newest first', () async {
    await record(1, usedAt: 100);
    await record(2, usedAt: 300);
    await record(3, usedAt: 200);

    expect((await store.load()).map((row) => row.entryId), [2, 3, 1]);
  });

  test('clear removes every row', () async {
    await record(1);
    await record(2);

    await store.clear();

    expect(await store.load(), isEmpty);
  });

  test('the stored limit defaults to the model default and is clamped', () async {
    final groups = WallpaperGroupStore(db);
    expect(await groups.readHistoryLimit(), GroupedWallpaperHistoryLimit.defaultLimit);

    await groups.writeHistoryLimit(4000);
    expect(await groups.readHistoryLimit(), GroupedWallpaperHistoryLimit.maxLimit);

    await groups.writeHistoryLimit(-5);
    expect(await groups.readHistoryLimit(), 0);
  });

  test('writing the limit does not delete recorded rows', () async {
    await record(1, usedAt: 100);
    await record(2, usedAt: 200);

    await WallpaperGroupStore(db).writeHistoryLimit(1);

    expect(await store.count(), 2);
    // The new limit only applies to the next shown photo.
    await record(3, usedAt: 300, limit: 1);
    expect((await store.load()).map((row) => row.entryId), [3]);
  });
}
