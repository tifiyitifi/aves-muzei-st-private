import 'package:aves/features/batch_ops/log.dart';
import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter/foundation.dart';

/// Small, cached view of the batch settings that are not part of the v1/v2
/// settings catalog.
///
/// They live in `appMeta` (the fork's key/value bookkeeping) because both are
/// run-time facts rather than user preferences with a default: the result mode
/// is read on every recorded item, and the pin marker must survive a preference
/// reset without re-pinning a folder the user unpinned.
class BatchSettings extends ChangeNotifier {
  static const String resultModeKey = 'batch.resultMode';
  static const String resultsPinnedKey = 'batch.resultsPinned';

  final AppDatabaseProvider? provider;

  new({this.provider});

  BatchResultMode _resultMode = BatchResultMode.replacePrevious;
  bool _loaded = false;
  Future<void>? _loading;

  BatchResultMode get resultMode => _resultMode;

  /// Loads the persisted values once; concurrent callers share the attempt.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final meta = AppMetaStore(await (provider ?? getIt<AppDatabaseProvider>()).open());
      final values = await meta.read({resultModeKey});
      _resultMode = BatchResultMode.parse(values[resultModeKey]);
    } catch (error, stack) {
      // A settings read must never block a run: fall back to the defaults.
      batchLog.w('failed to read batch settings', error, stack);
    } finally {
      _loaded = true;
      _loading = null;
      notifyListeners();
    }
  }

  Future<void> setResultMode(BatchResultMode mode) async {
    if (_resultMode == mode) return;
    _resultMode = mode;
    notifyListeners();
    await _write({resultModeKey: mode.name});
  }

  /// Claims the one-time "pin the results folder" action.
  ///
  /// Returns true only for the first successful run on this install. The marker
  /// is written before the caller pins, so a user who unpins the folder later is
  /// not overruled by a second claim.
  Future<bool> claimResultsPin() async {
    final meta = AppMetaStore(await (provider ?? getIt<AppDatabaseProvider>()).open());
    final values = await meta.read({resultsPinnedKey});
    if (values[resultsPinnedKey] == 'true') return false;
    await meta.write({resultsPinnedKey: 'true'});
    return true;
  }

  Future<void> _write(Map<String, String> values) async {
    try {
      final meta = AppMetaStore(await (provider ?? getIt<AppDatabaseProvider>()).open());
      await meta.write(values);
    } catch (error, stack) {
      batchLog.w('failed to write batch settings', error, stack);
    }
  }
}

/// Process-wide instance: the recorder, the settings page and the run sheet must
/// see the same cached mode.
final BatchSettings batchSettings = BatchSettings();
