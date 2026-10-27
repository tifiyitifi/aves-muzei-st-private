import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/services/visible_range_target_source.dart';

/// Exposes the wallpaper groups' ranges to the visible-range feature.
///
/// The groups are loaded lazily here: assigning the source at startup must not
/// wait for the bundled asset, and every entry point (`pinTargets`, write-back,
/// the group page) initializes the same memoized future anyway.
class WallpaperGroupTargetSource implements VisibleRangeTargetSource {
  final WallpaperGroupController controller;

  const new(this.controller);

  @override
  bool get targetsAreDraft => controller.draftActive;

  @override
  Future<List<VisibleRangePinTarget>> loadPinTargets() async {
    await controller.init();
    final targets = <VisibleRangePinTarget>[];
    for (final group in controller.groups) {
      final range = await controller.groupRange(group.id);
      targets.add(
        VisibleRangePinTarget(
          rangeId: wallpaperGroupRangeId(group.id),
          number: group.number,
          name: group.name,
          isGallery: false,
          // A locked range refuses writes unless its frozen permissions allow
          // editing, the same rule the range page applies.
          locked: range.locked && !range.permissions.edit,
        ),
      );
    }
    return targets;
  }

  @override
  Future<VisibleRange?> loadRange(String rangeId) async {
    await controller.init();
    return controller.loadRangeById(rangeId);
  }

  @override
  Future<void> saveRange(VisibleRange range) async {
    await controller.init();
    await controller.saveGroupRange(range);
  }
}

/// The source the composition root registers on `visibleRangeController`.
final WallpaperGroupTargetSource wallpaperGroupTargetSource = WallpaperGroupTargetSource(wallpaperGroupController);
