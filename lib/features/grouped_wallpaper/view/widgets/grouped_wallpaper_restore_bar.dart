import 'dart:async';

import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_restore_notice.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Puts the "the wallpaper stopped" strip above [child].
///
/// The loss happens while the app is not running, so the notice belongs where
/// the user lands, on every browsable surface, and not inside scrollable content
/// they may never reach. Re-applying always ends in the system picker: the
/// platform grants no silent rebind to a normal install.
///
/// The pages using this draw their own app bar inside the scroll view and add the
/// status bar padding themselves (there is no `Scaffold.appBar` to do it), so
/// while the strip occupies that inset the child must not add it again.
class GroupedWallpaperRestoreBody extends StatelessWidget {
  final Widget child;

  const new({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: groupedWallpaperRestoreNotice,
      builder: (context, _) {
        if (!groupedWallpaperRestoreNotice.isOffered) return child;
        return Column(
          children: [
            const GroupedWallpaperRestoreBar(),
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
            ),
          ],
        );
      },
    );
  }
}

/// The strip itself, including the status bar inset it took over.
class GroupedWallpaperRestoreBar extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.secondaryContainer,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 16,
          end: 4,
          top: MediaQuery.paddingOf(context).top + 2,
          bottom: 2,
        ),
        child: Row(
          children: [
            Icon(AIcons.wallpaperStopped, size: 18, color: colors.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.wallpaperGroupRestoreLost,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSecondaryContainer),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => unawaited(_reapply(context)),
              style: TextButton.styleFrom(foregroundColor: colors.onSecondaryContainer),
              child: Text(context.l10n.wallpaperGroupRestoreReapply),
            ),
            IconButton(
              onPressed: groupedWallpaperRestoreNotice.dismiss,
              icon: const Icon(AIcons.cancel, size: 18),
              color: colors.onSecondaryContainer,
              tooltip: context.l10n.wallpaperGroupRestoreDismiss,
            ),
          ],
        ),
      ),
    );
  }

  /// An OEM with no live-wallpaper picker would otherwise close the notice with
  /// nothing happening, so the failure is reported the way the page reports it.
  Future<void> _reapply(BuildContext context) async {
    final opened = await groupedWallpaperRestoreNotice.reapply();
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.wallpaperGroupChooserUnavailable)),
    );
  }
}
