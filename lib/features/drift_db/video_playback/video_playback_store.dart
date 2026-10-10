import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/model/viewer/video_playback.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// Owns the `videoPlayback` table (resume position per entry).
class VideoPlaybackStore {
  static const _table = 'videoPlayback';

  final AppDatabase db;

  new(this.db);

  Future<void> clear() async {
    final count = await db.delete(db.videoPlaybackTable).go();
    debugPrint('$runtimeType clear deleted $count rows');
  }

  Future<Set<VideoPlaybackRow>> loadAll() async {
    final result = <VideoPlaybackRow>{};
    for (final row in await selectAllRows(db, _table)) {
      final playback = VideoPlaybackRow.fromMap(row.data);
      if (playback != null) {
        result.add(playback);
      } else {
        debugPrint('$runtimeType failed to deserialize video playback from row=${row.data}');
      }
    }
    return result;
  }

  Future<VideoPlaybackRow?> load(int id) async {
    final rows = await db.customSelect('SELECT * FROM $_table WHERE id = ?', variables: [Variable(id)]).get();
    if (rows.isEmpty) return null;
    return VideoPlaybackRow.fromMap(rows.first.data);
  }

  Future<void> add(Set<VideoPlaybackRow> rows) async {
    if (rows.isEmpty) return;
    await db.batch((batch) {
      for (final row in rows) {
        batchInsertReplace(batch, db.videoPlaybackTable, row.toDbMap());
      }
    });
  }

  Future<void> remove(Set<int> ids) async {
    if (ids.isEmpty) return;
    await db.batch((batch) {
      for (final id in ids) {
        batch.deleteWhere(db.videoPlaybackTable, (t) => t.id.equals(id));
      }
    });
  }

  void deleteInBatch(Batch batch, int id) {
    batch.deleteWhere(db.videoPlaybackTable, (t) => t.id.equals(id));
  }
}
