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
  static const String shareRetentionDaysKey = 'batch.shareRetentionDays';
  static const String shareIntroSeenKey = 'batch.shareIntroSeen';

  /// Retention choices for the share folder, in days; `0` keeps output forever.
  static const List<int> shareRetentionOptions = [0, 1, 7, 30];

  /// A week covers the usual "process, share, come back later" window without
  /// letting the temporary folder grow unbounded.
  static const int defaultShareRetentionDays = 7;

  final AppDatabaseProvider? provider;

  new({this.provider});

  BatchResultMode _resultMode = BatchResultMode.replacePrevious;
  int _shareRetentionDays = defaultShareRetentionDays;
  bool _loaded = false;
  Future<void>? _loading;

  BatchResultMode get resultMode => _resultMode;

  int get shareRetentionDays => _shareRetentionDays;

  /// Reads a stored retention choice, falling back to the default.
  ///
  /// Only an offered value is honoured: a hand-edited or older row must not
  /// silently disable the cleanup or pick an arbitrary window.
  static int parseShareRetentionDays(String? value) {
    final days = int.tryParse(value ?? '');
    return days != null && shareRetentionOptions.contains(days) ? days : defaultShareRetentionDays;
  }

  /// Loads the persisted values once; concurrent callers share the attempt.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final meta = AppMetaStore(await (provider ?? getIt<AppDatabaseProvider>()).open());
      final values = await meta.read({resultModeKey, shareRetentionDaysKey});
      _resultMode = BatchResultMode.parse(values[resultModeKey]);
      _shareRetentionDays = parseShareRetentionDays(values[shareRetentionDaysKey]);
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

  Future<void> setShareRetentionDays(int days) async {
    if (_shareRetentionDays == days || !shareRetentionOptions.contains(days)) return;
    _shareRetentionDays = days;
    notifyListeners();
    await _write({shareRetentionDaysKey: '$days'});
  }

  /// Whether the one-time share explainer has been shown.
  ///
  /// The marker lives in `appMeta`, like the results pin, so resetting the
  /// preferences does not teach the same folder twice.
  Future<bool> hasSeenShareIntro() async {
    try {
      final meta = AppMetaStore(await (provider ?? getIt<AppDatabaseProvider>()).open());
      final values = await meta.read({shareIntroSeenKey});
      return values[shareIntroSeenKey] == 'true';
    } catch (error, stack) {
      batchLog.w('failed to read the share explainer marker', error, stack);
      // A missing marker must not block the run; the dialog is the lesser cost.
      return false;
    }
  }

  Future<void> markShareIntroSeen() => _write({shareIntroSeenKey: 'true'});

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
