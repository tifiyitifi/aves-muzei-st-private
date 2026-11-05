import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/logging/log.dart';
import 'package:flutter/foundation.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// Signals that rows changed behind the views that show them.
///
/// Two paths write the database outside a lens: the resume sync and the
/// MediaStore observer. Neither owns a view, so neither can refresh one; they
/// announce the write here and every live lens re-reads its window.
///
/// This is deliberately not the upstream `EntryAddedEvent`: `CollectionLens`
/// handles that one on the in-memory side, and synthesizing it over an
/// entry-free source would insert rows into a source the engine deliberately
/// keeps empty.
class PagedLibraryChanges extends ChangeNotifier {
  int _revision = 0;

  /// How many external changes have been announced, for tests and logs.
  int get revision => _revision;

  void bump() {
    _revision++;
    _log.d('paged library changed (revision=$_revision)');
    notifyListeners();
  }
}

/// The app-wide instance (same singleton style as `collectionPagingPrefs`).
final pagedLibraryChanges = PagedLibraryChanges();
