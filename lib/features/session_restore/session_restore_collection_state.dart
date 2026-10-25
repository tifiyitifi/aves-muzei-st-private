import 'package:aves/model/filters/filters.dart';

/// The filters of the media set currently on screen.
///
/// `CollectionPage` is the only writer. The snapshot needs it when the app is
/// paused, and the page may be rebuilt or replaced before that happens, so the
/// value cannot live in the page's state.
class SessionRestoreCollectionState {
  Set<CollectionFilter>? _filters;

  Set<CollectionFilter>? get filters => _filters;

  void note(Iterable<CollectionFilter> value) {
    _filters = value.toSet();
  }

  void clear() {
    _filters = null;
  }
}

final SessionRestoreCollectionState sessionRestoreCollectionState = SessionRestoreCollectionState();
