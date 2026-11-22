import 'package:aves/features/collection_paging/view/collection_view_hooks.dart';
import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:flutter/widgets.dart';

/// Merges a user's selection into the media set currently in scope.
///
/// A collection ANDs its filters, so leaving several plain album filters in the
/// set would show nothing. Album conditions are folded into one OR union, and
/// that union is flattened before it is rebuilt: appending overlapping albums
/// twice then composes into a single set of unique albums instead of nesting
/// unions or repeating a condition. Every non-album condition (date, rating,
/// the picker's photo restriction, ...) is kept as-is.
Set<CollectionFilter> mergeMediaSetFilters(
  Set<CollectionFilter>? base,
  Iterable<CollectionFilter> added,
) {
  final others = <CollectionFilter>{};
  final albums = <CollectionFilter>{};

  void collect(Iterable<CollectionFilter> filters) {
    for (final filter in filters) {
      if (_isAlbumScope(filter)) {
        if (filter is SetOrFilter) {
          albums.addAll(filter.innerFilters);
        } else {
          albums.add(filter);
        }
      } else {
        others.add(filter);
      }
    }
  }

  collect(base ?? const <CollectionFilter>{});
  collect(added);

  if (albums.isEmpty) return others;
  if (albums.length == 1) return {...others, albums.first};
  return {...others, SetOrFilter(albums)};
}

/// Resolves the media set [added] filters should be appended to.
///
/// A borrowed view (the wallpaper source picker) owns its own set, so it wins
/// over the app-wide slot: following the slot there would append to the library
/// and leave the pick. Outside a pick the slot holds the last shown media set.
Set<CollectionFilter> mediaSetAppendFilters(BuildContext context, Iterable<CollectionFilter> added) {
  final base = CollectionViewHooksScope.read(context)?.mediaSetFilters ?? mediaSetTab.currentFilters;
  return mergeMediaSetFilters(base, added);
}

/// Whether [filter] constrains the set to albums, including a union of them.
///
/// A reversed filter means "everything except", so it is not an album scope to
/// fold: changing it into a positive album union would invert its meaning. An
/// empty union is a deny-all condition and is likewise left alone.
bool _isAlbumScope(CollectionFilter filter) {
  if (filter.reversed) return false;
  return switch (filter) {
    AlbumBaseFilter() => true,
    SetOrFilter() => filter.innerFilters.isNotEmpty && filter.innerFilters.every((v) => v is AlbumBaseFilter && !v.reversed),
    _ => false,
  };
}
