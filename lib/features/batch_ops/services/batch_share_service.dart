import 'package:aves/features/batch_ops/log.dart';
import 'package:aves/features/batch_ops/model/batch_paths.dart';
import 'package:aves/features/batch_ops/services/batch_service.dart';
import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/utils/android_file_utils.dart';

/// Owns the copy & share output folder: where it is and when its files expire.
///
/// Share copies are temporary by design. The batch results service is not
/// reused here because nothing about a share copy is actionable: there is no
/// row, no replace and no move back, only a folder that must not grow forever.
class BatchShareService {
  final LocalMediaDb? db;
  final BatchService native;
  final BatchSettings? settings;

  const new({
    this.db,
    this.native = const BatchService(),
    this.settings,
  });

  LocalMediaDb get _localDb => db ?? localMediaDb;
  BatchSettings get _settings => settings ?? batchSettings;

  /// Absolute path of the share folder on primary storage.
  String get directory => pContext.join(androidFileUtils.primaryStorage, batchShareRelativeRoot);

  /// Removes share copies older than the configured retention.
  ///
  /// The cutoff uses the file's modified time, not the photo's capture time: a
  /// share copy of an old photo was still written now, so capture time would
  /// delete it immediately. A file exactly at the cutoff is kept, and an entry
  /// whose modified time is unknown is kept rather than guessed at.
  ///
  /// Only the share folder's direct children are read from the app's table, so
  /// a batch result, a source or a subfolder is never a candidate. Returns how
  /// many files were removed.
  Future<int> pruneExpired({DateTime? now}) async {
    var removed = 0;
    try {
      await _settings.ensureLoaded();
      final days = _settings.shareRetentionDays;
      if (days <= 0) return 0;

      final cutoff = (now ?? DateTime.now()).subtract(Duration(days: days)).millisecondsSinceEpoch;
      final entries = await _localDb.loadEntries(directory: directory);
      for (final entry in entries) {
        final modified = entry.dateModifiedMillis;
        if (modified == null || modified >= cutoff) continue;
        if (!await native.deleteResult(entry.uri)) {
          batchLog.w('failed to delete expired share copy ${entry.uri}');
          continue;
        }
        removed++;
        await _localDb.removeIds({entry.id});
      }
    } catch (error, stack) {
      // Housekeeping must never block the run or the settings page it precedes.
      batchLog.w('failed to prune the share folder', error, stack);
    }
    return removed;
  }
}

const batchShareService = BatchShareService();
