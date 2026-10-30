import 'dart:math';

import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_filter.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/filter_grids/common/list_details_theme.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// One wallpaper group on the page: a number, a name, its range and its state.
///
/// The subtitle is two lines: the range summary with the available count, then
/// the user's note when there is one. The lamp sits before the summary of an
/// enabled group, like the check icon on a range tile sits before its count; the
/// play icon marks the group the live wallpaper is actually playing, and the stop
/// icon sits on group 0 while nothing is playing. Both can be on at once. A
/// disabled group stays readable but dimmed and shows no lamp.
class WallpaperGroupTile extends StatelessWidget {
  /// Below this width the card cannot hold a range line and a count.
  static const double _compactWidth = 120;

  final WallpaperGroupFilter filter;
  final TileLayout tileLayout;
  final Size tileSize;

  /// Whether the page is selecting group cards.
  final bool selecting;

  /// Whether this card is in the page's multi-selection.
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const new({
    super.key,
    required this.filter,
    required this.tileLayout,
    required this.tileSize,
    this.selecting = false,
    this.selected = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = filter.enabled ? 1.0 : .55;
    final child = tileLayout == TileLayout.list ? _buildList(context) : _buildCard(context);
    // While selecting, the card highlights its selection; otherwise the border
    // marks the group whose range the page shows.
    final highlighted = selecting ? selected : filter.selected;
    return Opacity(
      opacity: opacity,
      child: highlighted ? _decorateSelected(context, child) : child,
    );
  }

  Widget _decorateSelected(BuildContext context, Widget child) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.primary, width: 2),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: child,
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = context.read<FilterListDetailsThemeData>();
    final extent = min(tileSize.height, 56.0);
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox.square(dimension: extent, child: _buildBadge(context, extent)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_label(context), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.titleStyle),
                  const SizedBox(height: 2),
                  // A list row only has room for the note when the theme's own
                  // measurement says a second caption line fits.
                  _buildSubtitleRow(context, theme.captionStyle.color, showNote: theme.showDate),
                ],
              ),
            ),
            _buildStateIcons(context, 20),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildBadge(context, tileSize.shortestSide),
                Positioned(top: 4, right: 4, child: _buildStateIcons(context, 18)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_label(context), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurface)),
                const SizedBox(height: 2),
                // A grid5 card is ~63 dp wide: it shows the count alone, since the
                // range line would push the number off the card, while a wider
                // card or a list row has room for both.
                _buildSubtitleRow(context, colors.onSurfaceVariant, compact: tileSize.width < _compactWidth),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The number, on the same neutral placeholder the range tiles use for a
  /// candidate without a cover.
  ///
  /// Group 0 (the off switch) is the only group without a lamp, and the lamp
  /// lives in the subtitle row so a short badge never overlaps the number.
  Widget _buildBadge(BuildContext context, double extent) {
    final brightness = Theme.of(context).brightness;
    final colors = Theme.of(context).colorScheme;
    final color = Color.lerp(
      colors.surfaceContainerHighest,
      colors.primaryContainer,
      (selecting ? selected : filter.selected) ? .7 : .25,
    )!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: .72)],
        ),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Center(
        child: Text(
          '${filter.number}',
          style: TextStyle(
            fontSize: min(extent * .36, 40),
            fontWeight: FontWeight.w600,
            color: brightness == Brightness.light ? Colors.black54 : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleRow(BuildContext context, Color? color, {bool showNote = true, bool compact = false}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final themeColors = theme.textTheme.bodySmall?.copyWith(color: color ?? colors.onSurfaceVariant);
    final rangeLine = _rangeLine(context, compact: compact);
    final note = filter.description;
    final showLamp = filter.enabled && !filter.isNone;
    final showNoteLine = showNote && note.isNotEmpty;
    if (rangeLine == null && !showLamp && !showNoteLine) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rangeLine != null || showLamp)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLamp) ...[
                Tooltip(
                  message: context.l10n.wallpaperGroupEnabled,
                  child: Icon(AIcons.visibleRangeActive, size: 14, color: colors.primary),
                ),
                const SizedBox(width: 4),
              ],
              if (rangeLine != null)
                Flexible(
                  child: Text(
                    rangeLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: themeColors,
                  ),
                ),
            ],
          ),
        if (showNoteLine)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: themeColors?.copyWith(color: colors.onSurfaceVariant.withValues(alpha: .8)),
            ),
          ),
      ],
    );
  }

  Widget _buildStateIcons(BuildContext context, double size) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selecting)
          Icon(selected ? AIcons.selected : AIcons.unselected, size: size, color: selected ? colors.primary : colors.onSurfaceVariant),
        if (filter.playing)
          Tooltip(
            message: context.l10n.wallpaperGroupPlaying,
            child: Icon(AIcons.wallpaperPlaying, size: size, color: colors.tertiary),
          ),
        if (filter.stopped)
          Tooltip(
            message: context.l10n.wallpaperGroupStopped,
            child: Icon(AIcons.wallpaperStopped, size: size, color: colors.onSurfaceVariant),
          ),
      ],
    );
  }

  String _label(BuildContext context) => wallpaperGroupNameOf(context, name: filter.name, number: filter.number, isNone: filter.isNone);

  /// The range summary with the available count, e.g. `+1 · 767 images`.
  ///
  /// The count is what the live wallpaper may use, not what browsing shows: the
  /// gallery range joins browsing only, and the availability label says so. The
  /// base name is only repeated when it differs from the group's own name, which
  /// leaves the count on the line instead of pushing it off a narrow card.
  ///
  /// [compact] is for a grid5 tile, ~63 dp wide: there only the count fits, and
  /// the range would cut the number off with an ellipsis.
  String? _rangeLine(BuildContext context, {bool compact = false}) {
    final count = filter.count;
    if (compact) return count == null ? null : context.l10n.wallpaperGroupCountShort(count);
    final l10n = context.l10n;
    final summary = visibleRangeGroupSummary(context, range: filter.range, groupName: filter.name, isNone: filter.isNone);
    if (count == null) return summary.isEmpty ? null : summary;
    return summary.isEmpty ? l10n.wallpaperGroupCount(count) : l10n.wallpaperGroupRangeLine(summary, count);
  }
}
