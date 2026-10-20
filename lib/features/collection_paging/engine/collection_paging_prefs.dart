import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_keys.dart';
import 'package:aves/features/logging/log.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Log channel owned by this feature (never a shared catch-all).
const String collectionPagingLogKey = 'log.collection_paging';

/// Channels this feature owns, opened in debug builds by `Log.init`.
///
/// Declared here rather than in `LogKeys`: the registry is for cross-cutting
/// channels, and a feature's diagnostics should not depend on someone
/// remembering to add them there.
const List<String> collectionPagingDebugLogKeys = [collectionPagingLogKey];

const _log = AreaKeyLog(collectionPagingLogKey);

/// User-tunable parameters of collection loading, independent of the settings
/// engine (v1/v2). Values persist in `SharedPreferences` under the
/// `collection_paging.*` namespace and fall back to the defaults below when
/// absent or unreadable, so a fresh install behaves as paged without any
/// migration.
///
/// The singleton self-loads on construction; [init] exists for callers (and
/// tests) that need the persisted values before first read.
class CollectionPagingPrefs extends ChangeNotifier {
  /// Hard ceiling for a window: a window is fully materialized, so this is a
  /// memory budget, not a preference.
  static const int maxWindowSize = 1000;

  /// Window sizes offered in the settings UI.
  static const List<int> windowSizePresets = [100, 200, 400];

  static const int defaultWindowSize = 200;

  static const int defaultPrefetchScreens = 2;

  static const int maxPrefetchScreens = 3;

  /// Entry counts offered as the large-collection threshold in the settings UI.
  static const List<int> largeThresholdPresets = [20000, 50000, 100000, 500000];

  /// Collections at or above this size use paged loading under [CollectionEngine.auto].
  ///
  /// The default is the smallest preset: a library that large already costs real
  /// memory to materialize, and the windowed path serves it without ever needing
  /// the whole list, so paging is the safer default and can still be raised.
  static const int defaultLargeThreshold = 20000;

  /// Hard ceiling for the threshold: above this a full load is never attempted.
  static const int maxLargeThreshold = 10000000;

  /// Whether the background catalogue asks before sweeping a large backlog.
  ///
  /// Off by default: cataloguing is the steady state of a paged collection
  /// (new rows are catalogued inline on sync), so a backlog is simply the part
  /// that has not been reached yet. The one-time explainer says so once, which
  /// leaves a question per launch with nothing to decide.
  static const bool defaultAskBeforeCatalog = false;

  /// Whether the browse-only notice bar is shown while the import runs.
  static const bool defaultBrowseOnlyBar = true;

  /// Rows imported before the collection paints for the first time.
  ///
  /// One screen's worth on a phone grid, which is what makes a fresh install
  /// browsable in a fraction of a second; the rest streams in behind it.
  static const int firstImportBatchSize = 250;

  CollectionEngine _engine = CollectionEngine.defaultEngine;

  int _windowSize = defaultWindowSize;

  int _prefetchScreens = defaultPrefetchScreens;

  int _largeThreshold = defaultLargeThreshold;

  bool _askBeforeCatalog = defaultAskBeforeCatalog;

  bool _browseOnlyBar = defaultBrowseOnlyBar;

  bool _importExplained = false;

  bool _importComplete = false;

  bool _loaded = false;

  new() {
    unawaited(init());
  }

  CollectionEngine get engine => _engine;

  int get windowSize => _windowSize;

  int get prefetchScreens => _prefetchScreens;

  int get largeThreshold => _largeThreshold;

  bool get askBeforeCatalog => _askBeforeCatalog;

  /// Whether the browse-only notice bar is shown during the first import.
  bool get browseOnlyBar => _browseOnlyBar;

  /// Whether the one-time background-organization explainer has been shown.
  bool get importExplained => _importExplained;

  /// Whether the library has been fully imported at least once.
  bool get importComplete => _importComplete;

  /// Whether persisted values have been read. Getters return defaults before.
  bool get isLoaded => _loaded;

  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _engine = CollectionEngine.tryParse(prefs.getString(CollectionPagingKeys.engine)) ?? CollectionEngine.defaultEngine;
      _windowSize = clampWindowSize(prefs.getInt(CollectionPagingKeys.windowSize) ?? defaultWindowSize);
      _prefetchScreens = (prefs.getInt(CollectionPagingKeys.prefetchScreens) ?? defaultPrefetchScreens).clamp(0, maxPrefetchScreens);
      _largeThreshold = clampLargeThreshold(prefs.getInt(CollectionPagingKeys.largeThreshold) ?? defaultLargeThreshold);
      _askBeforeCatalog = prefs.getBool(CollectionPagingKeys.askBeforeCatalog) ?? defaultAskBeforeCatalog;
      _browseOnlyBar = prefs.getBool(CollectionPagingKeys.browseOnlyBar) ?? defaultBrowseOnlyBar;
      _importExplained = prefs.getBool(CollectionPagingKeys.importExplained) ?? false;
      _importComplete = prefs.getBool(CollectionPagingKeys.importComplete) ?? false;
    } catch (error, stack) {
      _log.w('failed to load collection paging prefs, using defaults', error, stack);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEngine(CollectionEngine engine) async {
    if (engine == _engine) return;
    _engine = engine;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(CollectionPagingKeys.engine, engine.name);
    } catch (error, stack) {
      _log.e('failed to persist collection engine=${engine.name}', error, stack);
    }
  }

  Future<void> setWindowSize(int size) async {
    final clamped = clampWindowSize(size);
    if (clamped == _windowSize) return;
    _windowSize = clamped;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setInt(CollectionPagingKeys.windowSize, clamped);
    } catch (error, stack) {
      _log.e('failed to persist collection window size=$clamped', error, stack);
    }
  }

  Future<void> setPrefetchScreens(int screens) async {
    final clamped = screens.clamp(0, maxPrefetchScreens);
    if (clamped == _prefetchScreens) return;
    _prefetchScreens = clamped;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setInt(CollectionPagingKeys.prefetchScreens, clamped);
    } catch (error, stack) {
      _log.e('failed to persist collection prefetch screens=$clamped', error, stack);
    }
  }

  Future<void> setLargeThreshold(int threshold) async {
    final clamped = clampLargeThreshold(threshold);
    if (clamped == _largeThreshold) return;
    _largeThreshold = clamped;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setInt(CollectionPagingKeys.largeThreshold, clamped);
    } catch (error, stack) {
      _log.e('failed to persist collection large threshold=$clamped', error, stack);
    }
  }

  Future<void> setAskBeforeCatalog(bool ask) async {
    if (ask == _askBeforeCatalog) return;
    _askBeforeCatalog = ask;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(CollectionPagingKeys.askBeforeCatalog, ask);
    } catch (error, stack) {
      _log.e('failed to persist collection ask-before-catalog=$ask', error, stack);
    }
  }

  /// Records that the one-time explainer was shown, so it never reappears.
  Future<void> setImportExplained() async {
    if (_importExplained) return;
    _importExplained = true;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(CollectionPagingKeys.importExplained, true);
    } catch (error, stack) {
      _log.e('failed to persist the import explainer flag', error, stack);
    }
  }

  /// Records whether the library is fully imported.
  ///
  /// Written as `false` when an import starts and `true` when it completes, so
  /// an interrupted run resumes on the next launch instead of leaving a
  /// permanently partial collection.
  Future<void> setImportComplete(bool complete) async {
    if (complete == _importComplete) return;
    _importComplete = complete;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(CollectionPagingKeys.importComplete, complete);
    } catch (error, stack) {
      _log.e('failed to persist the import-complete flag=$complete', error, stack);
    }
  }

  /// Toggles the browse-only notice bar.
  Future<void> setBrowseOnlyBar(bool show) async {
    if (show == _browseOnlyBar) return;
    _browseOnlyBar = show;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(CollectionPagingKeys.browseOnlyBar, show);
    } catch (error, stack) {
      _log.e('failed to persist the browse-only bar flag=$show', error, stack);
    }
  }

  /// Clamps a requested window size into the legal `1..[maxWindowSize]` range.
  ///
  /// Pure, so persisted values from older builds and the UI presets share one
  /// definition of what is legal.
  static int clampWindowSize(int size) => size < 1 ? 1 : (size > maxWindowSize ? maxWindowSize : size);

  /// Clamps a requested large-collection threshold into `1..[maxLargeThreshold]`.
  static int clampLargeThreshold(int threshold) => threshold < 1 ? 1 : (threshold > maxLargeThreshold ? maxLargeThreshold : threshold);
}

/// The app-wide collection paging preferences (mirrors the `settings` and
/// `settingsEngineController` singleton style).
final CollectionPagingPrefs collectionPagingPrefs = CollectionPagingPrefs();
