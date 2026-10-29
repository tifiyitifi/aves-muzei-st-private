import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Lets the user read another group's usage history.
///
/// Every group is listed with its record count, so a group that never showed a
/// photo reads as empty at a glance instead of looking broken after switching.
/// Returns the chosen group id, or null when dismissed.
Future<String?> showGroupedWallpaperHistoryGroupDialog(
  BuildContext context, {
  required List<WallpaperGroup> groups,
  required Map<String, int> counts,
  required String? selectedGroupId,
}) {
  final l10n = context.l10n;
  final theme = Theme.of(context);
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.wallpaperGroupHistorySwitchGroup),
      children: [
        for (final group in groups)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, group.id),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: group.id == selectedGroupId ? const Icon(AIcons.checked, size: 20) : null,
                ),
                Expanded(child: Text(wallpaperGroupName(context, group), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 12),
                Text(
                  l10n.wallpaperGroupHistoryCount(counts[group.id] ?? 0),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
