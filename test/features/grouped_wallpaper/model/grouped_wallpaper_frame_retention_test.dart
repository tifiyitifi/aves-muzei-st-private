import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_frame_retention.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperFrameRetention`: the switch that caps how many baked frames
/// the renderer keeps, and the tolerance of a value read back from a file another
/// build wrote.
void main() {
  test('the default keeps the behaviour every earlier build had', () {
    expect(GroupedWallpaperFrameRetention.defaultRetention, GroupedWallpaperFrameRetention.all);
  });

  test('an unknown name reads as the default', () {
    expect(GroupedWallpaperFrameRetention.tryParse('displayed'), GroupedWallpaperFrameRetention.displayed);
    expect(GroupedWallpaperFrameRetention.tryParse('auto'), GroupedWallpaperFrameRetention.auto);
    expect(GroupedWallpaperFrameRetention.tryParse(null), GroupedWallpaperFrameRetention.defaultRetention);
    expect(GroupedWallpaperFrameRetention.tryParse('DISPLAYED'), GroupedWallpaperFrameRetention.defaultRetention);
    expect(GroupedWallpaperFrameRetention.tryParse(7), GroupedWallpaperFrameRetention.defaultRetention);
  });
}
