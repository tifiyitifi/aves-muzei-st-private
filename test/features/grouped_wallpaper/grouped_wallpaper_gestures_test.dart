import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gesture defaults are muscle memory: a double tap opens the immersive
/// view, and the three-finger tap moves to the next photo.
void main() {
  test('defaults bind double tap to the view page and three fingers to next', () {
    const gestures = GroupedWallpaperGestures();
    expect(gestures.doubleTap, GroupedWallpaperTapAction.viewArtwork);
    expect(gestures.threeFinger, GroupedWallpaperTapAction.nextArtwork);
  });

  test('a gesture map round trips through JSON with the new defaults', () {
    const gestures = GroupedWallpaperGestures();
    final map = gestures.toJsonMap();
    expect(map['doubleTap'], 'viewArtwork');
    expect(map['threeFinger'], 'nextArtwork');
    expect(GroupedWallpaperGestures.fromJsonMap(map), gestures);
  });

  test('missing or unknown values fall back to the new defaults', () {
    expect(GroupedWallpaperGestures.fromJsonString(null), const GroupedWallpaperGestures());
    expect(GroupedWallpaperGestures.fromJsonString(''), const GroupedWallpaperGestures());
    expect(GroupedWallpaperGestures.fromJsonString('not json'), const GroupedWallpaperGestures());
    expect(
      GroupedWallpaperGestures.fromJsonString('{"doubleTap":"bogus","threeFinger":"bogus"}'),
      const GroupedWallpaperGestures(),
    );
    expect(GroupedWallpaperGestures.fromJsonMap(const {}), const GroupedWallpaperGestures());
  });

  test('an explicit binding survives the defaults', () {
    const gestures = GroupedWallpaperGestures(doubleTap: GroupedWallpaperTapAction.none, threeFinger: GroupedWallpaperTapAction.viewArtwork);
    expect(
      GroupedWallpaperGestures.fromJsonString('{"doubleTap":"none","threeFinger":"viewArtwork"}'),
      gestures,
    );
  });
}
