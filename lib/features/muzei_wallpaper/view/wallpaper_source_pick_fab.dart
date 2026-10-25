import 'package:aves/features/muzei_wallpaper/view/wallpaper_source_pick_session.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The picker's confirm button.
///
/// Both modes use a labelled button, and the label says which question is being
/// answered: the filter set, or the photo that was tapped. A round icon button
/// would look like the app's own action FAB while doing something the user
/// cannot read from an icon.
class WallpaperSourcePickFab extends StatelessWidget {
  final WallpaperSourcePickSession session;
  final CollectionLens collection;

  const new({
    super.key,
    required this.session,
    required this.collection,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    switch (session.mode) {
      case WallpaperSourcePickMode.filters:
        // An empty set has nothing to confirm: the wallpaper would resolve to
        // no artwork, so the button stays disabled instead.
        return ListenableBuilder(
          listenable: collection,
          builder: (context, _) {
            final canConfirm = collection.entryCount > 0;
            return FloatingActionButton.extended(
              onPressed: canConfirm ? () => session.confirmFilters(collection.filters) : null,
              icon: const Icon(AIcons.apply),
              label: Text(l10n.muzeiWallpaperSourceUseFilters),
            );
          },
        );
      case WallpaperSourcePickMode.single:
        return ValueListenableBuilder<int?>(
          valueListenable: session.pickedEntryNotifier,
          builder: (context, pickedEntryId, _) {
            return FloatingActionButton.extended(
              onPressed: pickedEntryId == null ? null : session.confirmPicked,
              icon: const Icon(AIcons.image),
              label: Text(l10n.muzeiWallpaperSourceUsePickedPhoto),
            );
          },
        );
    }
  }
}
