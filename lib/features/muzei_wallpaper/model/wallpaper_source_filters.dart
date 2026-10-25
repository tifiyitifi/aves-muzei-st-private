import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/ref/mime_types.dart';

/// The filter the wallpaper-source picker always applies but never shows.
///
/// A wallpaper is a still image, so the picker is a photo library. Exposing the
/// restriction as a chip would also let it leak into the pages the picker opens
/// (albums, search), which the user reads as "the app suddenly hides videos".
/// It therefore lives in the lens only, and the picker marks it hidden and
/// locked.
final Set<CollectionFilter> wallpaperPhotoRestriction = Set.unmodifiable({MimeFilter.image});

/// Drops every video restriction and guarantees a positive photo restriction.
///
/// Aves' search sheet can add any MIME filter after the picker is open. A video
/// one would make the wallpapered set empty (and is stripped silently, exactly
/// like the implicit restriction), while a negated image one would turn the set
/// into "everything but photos". A positive image subtype the user picked on
/// purpose is kept: it is still a photo restriction, and hiding it would make
/// the chip they just added disappear.
Set<CollectionFilter> normalizeWallpaperFilters(Iterable<CollectionFilter> filters) {
  final kept = <CollectionFilter>[];
  var hasPhotoRestriction = false;
  for (final filter in filters) {
    if (filter is MimeFilter) {
      final mime = filter.mime.toLowerCase();
      if (_isVideoMime(mime)) continue;
      if (_isPhotoMime(mime)) {
        if (filter.reversed) continue;
        hasPhotoRestriction = true;
      }
    }
    kept.add(filter);
  }
  if (!hasPhotoRestriction) kept.add(MimeFilter.image);
  return kept.toSet();
}

/// Removes the implicit photo restriction before a filter set leaves the picker.
///
/// The repository adds it again when it compiles the predicate, so returning it
/// would only make the persisted source carry a condition the editor has to keep
/// re-hiding.
Set<CollectionFilter> withoutWallpaperPhotoRestriction(Iterable<CollectionFilter> filters) {
  return filters.where((filter) => filter != MimeFilter.image).toSet();
}

/// Whether [mime] denotes a video (including the `video/*` wildcard).
bool _isVideoMime(String mime) => mime == MimeTypes.anyVideo || mime.startsWith('video/');

/// Whether [mime] denotes an image (including the `image/*` wildcard).
bool _isPhotoMime(String mime) => mime == MimeTypes.anyImage || mime.startsWith('image/');
