import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_filters.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// What the wallpaper source picker returns to the source page.
enum WallpaperSourcePickMode {
  /// The whole filter set, confirmed with the button.
  filters,

  /// The photo the user picked and confirmed.
  single,
}

/// The picker's answer.
sealed class WallpaperSourcePickResult {
  const new();
}

final class WallpaperSourcePickFiltersResult extends WallpaperSourcePickResult {
  final Set<CollectionFilter> filters;

  const new(this.filters);
}

final class WallpaperSourcePickEntryResult extends WallpaperSourcePickResult {
  final AvesEntry entry;

  const new(this.entry);
}

/// State shared by every page of one pick.
///
/// The picker is the app's own collection and album pages, so the state cannot
/// live in a page: a page is disposed as soon as the user opens another one.
/// It lives above the picker's navigator instead, and the pages read it through
/// the collection view hooks.
class WallpaperSourcePickSession {
  final WallpaperSourcePickMode mode;
  final void Function(WallpaperSourcePickResult result) onConfirm;

  /// The entry the user picked in single mode, for the tiles to draw.
  final ValueNotifier<int?> pickedEntryNotifier = ValueNotifier(null);

  /// Whether the pick opens on the album list instead of a media set.
  ///
  /// Finding a photo is faster by album, and "all photos" is not a set worth
  /// showing as a grid before the user narrows it: both start from the album
  /// list. A configured filter set is exactly the media set the user wants, so
  /// it opens there.
  final bool startsOnAlbums;

  /// The set being edited, used to keep its other conditions when an album is
  /// opened.
  ///
  /// Aves' album page opens a plain album, but the picker is editing one filter
  /// set: changing the album must not silently drop the date, rating or
  /// favourite conditions the user already chose. The merged set is visible as
  /// chips, so the user can still remove any of them.
  Set<CollectionFilter> _baseFilters;

  AvesEntry? _pickedEntry;

  bool _disposed = false;

  new({
    required this.mode,
    required this.onConfirm,
    Set<CollectionFilter> initialFilters = const {},
  }) : startsOnAlbums = mode == WallpaperSourcePickMode.single || withoutWallpaperPhotoRestriction(initialFilters).isEmpty,
       _baseFilters = normalizeWallpaperFilters(initialFilters);

  bool get isSingle => mode == WallpaperSourcePickMode.single;

  /// The set the media-set destination opens inside the picker.
  ///
  /// The bottom bar normally reopens the view it last showed (an app-wide slot),
  /// but inside a pick that slot belongs to the library: following it would
  /// leave the picker's set. The picker owns this answer instead.
  Set<CollectionFilter> get mediaSetFilters => _baseFilters;

  void pick(AvesEntry? entry) {
    _pickedEntry = entry;
    pickedEntryNotifier.value = entry?.id;
  }

  /// Applies the picker's photo restriction and keeps the set's other
  /// conditions when the page only names an album.
  Set<CollectionFilter> augmentFilters(Iterable<CollectionFilter> requested) {
    final normalized = normalizeWallpaperFilters(requested);
    if (!_isAlbumOnly(normalized)) return normalized;
    final others = _baseFilters.where((filter) => filter != MimeFilter.image && !_isAlbumScope(filter));
    return normalizeWallpaperFilters({...normalized, ...others});
  }

  /// Keeps the view's filter set valid after the user edits it.
  Set<CollectionFilter> normalizeFilters(Set<CollectionFilter> filters) {
    final normalized = normalizeWallpaperFilters(filters);
    // The view's filters changed, so the picked photo may no longer be in it:
    // the user is asking a new question. A live query is part of the view, not
    // of the set being edited, so it never follows an album change.
    _baseFilters = normalized.where((filter) => !_isLiveQuery(filter)).toSet();
    _clearPickSafely();
    return normalized;
  }

  /// Adopts the view that just opened as the set being edited.
  void adoptView(CollectionLens collection) {
    _baseFilters = collection.filters.where((filter) => !_isLiveQuery(filter)).toSet();
    _clearPickSafely();
  }

  /// Confirms the filters the current view carries.
  ///
  /// The implicit photo restriction is dropped: it is the picker's own
  /// constraint, and the source repository adds it back when it compiles the
  /// predicate.
  void confirmFilters(Set<CollectionFilter> filters) {
    if (mode != WallpaperSourcePickMode.filters) return;
    onConfirm(WallpaperSourcePickFiltersResult(withoutWallpaperPhotoRestriction(filters)));
  }

  void confirmPicked() {
    final entry = _pickedEntry;
    if (mode != WallpaperSourcePickMode.single || entry == null) return;
    onConfirm(WallpaperSourcePickEntryResult(entry));
  }

  void dispose() {
    _disposed = true;
    pickedEntryNotifier.dispose();
  }

  /// Clears the pick without notifying tiles during a build.
  ///
  /// A page opening runs inside the frame's build phase. Notifying a mounted
  /// tile there would be a `setState` during build, so the clear waits for the
  /// frame to end.
  void _clearPickSafely() {
    if (_disposed) return;
    if (_pickedEntry == null && pickedEntryNotifier.value == null) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) pick(null);
      });
    } else {
      pick(null);
    }
  }

  /// Whether [filters] name only albums, so its album part is what changes.
  static bool _isAlbumOnly(Set<CollectionFilter> filters) {
    var hasAlbum = false;
    for (final filter in filters) {
      if (filter == MimeFilter.image) continue;
      if (!_isAlbumScope(filter)) return false;
      hasAlbum = true;
    }
    return hasAlbum;
  }

  /// Whether [filter] constrains the set to albums, including a union of them.
  static bool _isAlbumScope(CollectionFilter filter) {
    switch (filter) {
      case AlbumBaseFilter():
        return true;
      case SetOrFilter():
        final inner = filter.innerFilters;
        return inner.isNotEmpty && inner.every((v) => v is AlbumBaseFilter);
      default:
        return false;
    }
  }

  /// Whether [filter] is the view's live search text.
  ///
  /// It is transient: a view shows its own query bar, and carrying the text
  /// into the next album would filter it without showing why.
  static bool _isLiveQuery(CollectionFilter filter) => filter is QueryFilter && filter.live;
}
