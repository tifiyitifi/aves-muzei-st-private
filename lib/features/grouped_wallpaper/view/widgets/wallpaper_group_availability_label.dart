import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Whether browsing currently shows what the wallpaper may use.
///
/// The label describes the gallery range, not the wallpaper: a restricted range
/// narrows browsing, while the live wallpaper still reads its own group range.
/// Temporarily ignoring the gallery range makes browsing unrestricted, so the
/// label says the wallpaper is available even though the saved range still
/// restricts it.
class WallpaperGroupAvailabilityLabel extends StatelessWidget {
  /// Whether the page temporarily ignores the gallery range.
  final bool gallerySuspended;

  const new({super.key, required this.gallerySuspended});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: visibleRangeController,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final restricted = visibleRangeController.gallery.isRestricted && !gallerySuspended;
        return Tooltip(
          message: context.l10n.wallpaperGroupAvailableBrowsingTooltip,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                restricted ? AIcons.visibleRangeInactive : AIcons.checked,
                size: 14,
                color: restricted ? colors.onSurfaceVariant : colors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                restricted ? context.l10n.wallpaperGroupAvailableBrowsingRestricted : context.l10n.wallpaperGroupAvailable,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}
