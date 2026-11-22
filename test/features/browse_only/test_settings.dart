import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter/foundation.dart';

/// The settings a browse widget reads through the provider, without the device
/// behind them.
///
/// `useTvLayout` asks the device singleton, which the tests never fill from the
/// platform plugins, so every read would throw; the thumbnail overlays ask the
/// display settings. Only the navigation items are drivable.
class BrowseTestSettings extends ChangeNotifier implements Settings {
  List<AvesNavItem> items = const [];

  @override
  List<AvesNavItem> get bottomNavigationActions => items;

  @override
  set bottomNavigationActions(List<AvesNavItem>? value) {
    items = value ?? const [];
    notifyListeners();
  }

  @override
  bool get useTvLayout => false;

  @override
  bool get showThumbnailFavourite => false;

  @override
  bool get showThumbnailHdr => false;

  @override
  ThumbnailOverlayLocationIcon get thumbnailLocationIcon => .none;

  @override
  ThumbnailOverlayTagIcon get thumbnailTagIcon => .none;

  @override
  bool get showThumbnailMotionPhoto => false;

  @override
  bool get showThumbnailRating => false;

  @override
  bool get showThumbnailRaw => false;

  @override
  bool get showThumbnailVideoDuration => false;

  @override
  bool get animate => false;

  @override
  bool get enableBlurEffect => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName} on the test settings');
}
