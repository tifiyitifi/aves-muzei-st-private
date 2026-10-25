import 'package:aves/features/muzei_wallpaper/view/wallpaper_source_pick_session.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Confirms the photo on screen as the single wallpaper picture.
///
/// The viewer is a natural place to choose: the user can zoom, inspect and
/// compare, then answer without going back to the grid. The button follows the
/// current page, so it always names the photo that is visible.
class WallpaperSourcePickViewerAction extends StatelessWidget {
  final WallpaperSourcePickSession session;
  final AvesEntry entry;

  const new({
    super.key,
    required this.session,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 16, bottom: 8),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FloatingActionButton.extended(
          heroTag: null,
          onPressed: () {
            session.pick(entry);
            session.confirmPicked();
          },
          icon: const Icon(AIcons.image),
          label: Text(context.l10n.muzeiWallpaperSourceUsePickedPhoto),
        ),
      ),
    );
  }
}
