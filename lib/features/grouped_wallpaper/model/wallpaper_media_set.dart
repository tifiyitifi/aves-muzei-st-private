import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';

/// The entries a wallpaper group is allowed to use: every image its visible
/// range keeps.
///
/// This is the single entry point for the media set. The wallpaper engine must
/// not compose filters itself, so "images only" (videos never participate, like
/// Muzei) and the fail-closed behaviour stay in one place and cannot differ
/// between the engine, the page and the tests.
///
/// A null (or unrestricted) range still means "all images". A range whose
/// bundled folder could not be resolved carries a deny-all base, so the result is
/// empty rather than everything — see `wallpaperDenyAllFilter`.
CollectionFilter? wallpaperMediaSetFilter(VisibleRange? range) {
  final resolved = range?.resolve();
  if (resolved == null) return MimeFilter.image;
  return SetAndFilter({MimeFilter.image, resolved});
}
