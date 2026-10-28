import 'dart:math';

import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_filter.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/filter_grids/common/list_details_theme.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// One wallpaper group on the page: a number, a name, a note and its state.
///
/// The lamp sits on the number badge of an enabled group; the play icon marks the
/// group the live wallpaper is actually playing, and the stop icon sits on group
/// 0 while nothing is playing. Both can be on at once. A disabled group stays
/// readable but dimmed, shows no lamp, and the note falls back to the image count.
class WallpaperGroupTile extends StatelessWidget {
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
                  _buildSubtitleRow(context, theme.captionStyle.color),
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
                _buildSubtitleRow(context, colors.onSurfaceVariant),
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
  /// An enabled real group also shows the lamp on the lower part of the badge:
  /// it is what "this group may be played" looks like, and group 0 (the off
  /// switch) never has it.
  Widget _buildBadge(BuildContext context, double extent) {
    final brightness = Theme.of(context).brightness;
    final colors = Theme.of(context).colorScheme;
    final color = Color.lerp(
      colors.surfaceContainerHighest,
      colors.primaryContainer,
      (selecting ? selected : filter.selected) ? .7 : .25,
    )!;
    final showLamp = filter.enabled && !filter.isNone;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: .72)],
        ),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              '${filter.number}',
              style: TextStyle(
                fontSize: min(extent * .36, 40),
                fontWeight: FontWeight.w600,
                color: brightness == Brightness.light ? Colors.black54 : Colors.white70,
              ),
            ),
          ),
          if (showLamp)
            Positioned(
              left: 0,
              right: 0,
              bottom: extent * .1,
              child: Center(
                child: Tooltip(
                  message: context.l10n.wallpaperGroupEnabled,
                  child: Icon(AIcons.visibleRangeActive, size: min(extent * .2, 18), color: colors.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubtitleRow(BuildContext context, Color? color) {
    final theme = Theme.of(context);
    final subtitle = _subtitle(context);
    if (subtitle == null) return const SizedBox.shrink();
    return Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(color: color ?? theme.colorScheme.onSurfaceVariant),
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

  /// The group's note, else how many images its range resolves to.
  String? _subtitle(BuildContext context) {
    if (filter.description.isNotEmpty) return filter.description;
    final count = filter.count;
    if (count == null) return null;
    return settings.avesLocale.decimalNumberFormat().format(count);
  }
}
