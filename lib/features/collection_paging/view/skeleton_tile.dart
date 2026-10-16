import 'package:aves/widgets/common/thumbnail/decorated.dart';
import 'package:aves/widgets/common/thumbnail/image.dart';
import 'package:material_ui/material_ui.dart';

/// Placeholder grid tile for an unloaded window position.
///
/// Fixed extent (from the layout), so the sliver geometry never shifts while
/// rows fetch in the background. Inert: no tap, no hero, no selection.
class SkeletonTile extends StatelessWidget {
  final Size tileSize;

  const new({super.key, required this.tileSize});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ThumbnailImage.computeLoadingBackgroundColor(hashCode * 10, brightness).withValues(alpha: .9),
        border: Border.all(
          color: DecoratedThumbnail.borderColor(context),
          width: DecoratedThumbnail.borderWidth(context),
        ),
      ),
      child: SizedBox.fromSize(size: tileSize),
    );
  }
}
