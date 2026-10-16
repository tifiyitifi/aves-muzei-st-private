import 'package:aves/widgets/common/thumbnail/image.dart';
import 'package:material_ui/material_ui.dart';

/// Placeholder viewer page for an unloaded window position.
///
/// Same loading-background language as the grid skeleton tiles, plus a spinner
/// since a full page of flat colour reads as broken. Inert: no hero, no
/// controllers, no info. The pager swaps in the real page when the window
/// fills.
class ViewerSkeletonPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ThumbnailImage.computeLoadingBackgroundColor(hashCode * 10, brightness).withValues(alpha: .9),
      ),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
