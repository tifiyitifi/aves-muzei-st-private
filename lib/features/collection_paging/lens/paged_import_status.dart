import 'package:flutter/foundation.dart';

/// Live state of the one-time import that fills an empty database, shared by
/// the lens that runs it and the surfaces that report it.
///
/// This is what makes "browse first, organize in the background" honest: the
/// grid paints after the first batch, the rest streams in behind it, and the
/// app bar can say how far it has got (`done / total`) for as long as the
/// collection is not yet the whole library.
class PagedImportStatus extends ChangeNotifier {
  bool _active = false;
  int _done = 0;
  int _total = 0;
  bool _explainerPending = false;

  /// Whether rows are still being imported.
  bool get active => _active;

  /// Rows written so far.
  int get done => _done;

  /// Rows MediaStore reported for the import scope, or 0 while unknown.
  int get total => _total;

  /// Whether the one-time explainer should be shown now.
  bool get explainerPending => _explainerPending;

  /// Starts a run. [total] is usually unknown at first and filled in by
  /// [update] once the platform count lands.
  void begin({int total = 0}) {
    _active = true;
    _done = 0;
    _total = total;
    notifyListeners();
  }

  /// Reports progress. [total] of 0 keeps the previous denominator.
  void update(int done, {int total = 0}) {
    final nextTotal = total > 0 ? total : _total;
    if (_done == done && _total == nextTotal) return;
    _done = done;
    _total = nextTotal;
    notifyListeners();
  }

  /// Ends the run; the collection is whole.
  void end() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }

  /// Raises the one-time explainer, if it is not already up.
  void requestExplainer() {
    if (_explainerPending) return;
    _explainerPending = true;
    notifyListeners();
  }

  /// Clears the pending explainer once a surface has shown it.
  void clearExplainer() {
    if (!_explainerPending) return;
    _explainerPending = false;
    notifyListeners();
  }

  /// Forgets everything, for tests and a disposed source.
  @visibleForTesting
  void reset() {
    _active = false;
    _done = 0;
    _total = 0;
    _explainerPending = false;
    notifyListeners();
  }
}

/// The app's single import status (mirrors the `collectionPagingPrefs` style):
/// the lens writes, the app bar and the explainer read.
final PagedImportStatus pagedImportStatus = PagedImportStatus();
