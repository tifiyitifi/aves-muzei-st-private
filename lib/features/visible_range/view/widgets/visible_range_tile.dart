import 'dart:math';

import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves/widgets/common/thumbnail/image.dart';
import 'package:aves/widgets/filter_grids/common/covered_filter_chip.dart';
import 'package:aves/widgets/filter_grids/common/filter_chip_grid_decorator.dart';
import 'package:aves/widgets/filter_grids/common/list_details_theme.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// One tile of the visible-range grid.
///
/// It reads like a regular covered chip: a cover, a name and a number. The only
/// extra is the state icon in the details row, which tells whether the candidate
/// takes part in the current range (checked) or not (blocked). Description and
/// kind icon are left out on purpose: the page is a checklist, not an editor.
///
/// Selection is passed in as plain values instead of read from a
/// `Selection` provider: the same tile is also rendered by the pinch-zoom
/// preview, which lives in an `OverlayEntry` outside the page's provider tree,
/// and the wallpaper page provides a differently typed selection. Keeping the
/// tile provider-free makes it valid in all three places.
class VisibleRangeTile extends StatelessWidget {
  final FilterGridItem<VisibleRangeCandidateFilter> gridItem;
  final VisibleRangeCandidateStats? stats;
  final TileLayout tileLayout;
  final Size tileSize;

  /// Footer copies are not part of the grid's selection: tapping one cancels
  /// the condition instead.
  final bool summary;

  /// The result chip shows only its count: it is not a condition that can be
  /// toggled on and off.
  final bool showStateIcon;

  /// Whether this tile takes part in the grid's selection at all.
  final bool selectable;

  /// Whether the page is in selection mode.
  final bool selecting;

  /// Whether this tile is currently selected.
  final bool selected;

  /// Layout-specific text for a placeholder tile; empty keeps the candidate's.
  final String labelOverride;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final VoidCallback? onLongPress;

  const new({
    super.key,
    required this.gridItem,
    required this.stats,
    required this.tileLayout,
    required this.tileSize,
    this.summary = false,
    this.showStateIcon = true,
    this.selectable = false,
    this.selecting = false,
    this.selected = false,
    this.labelOverride = '',
    this.onTap,
    this.onRemove,
    this.onLongPress,
  });

  VisibleRangeCandidate get candidate => gridItem.filter.candidate;

  @override
  Widget build(BuildContext context) {
    // The list row is wider than it is tall and lays the chip out in a fixed
    // square on the start side, so its extent is the row height. Grid and mosaic
    // keep the album chip's square extent.
    final extent = tileLayout == TileLayout.list ? tileSize.height : tileSize.shortestSide;
    if (tileLayout == TileLayout.list) {
      return _buildList(context, extent);
    }
    return _decorate(
      context,
      extent,
      _buildChip(context, extent, showText: true),
    );
  }

  Widget _decorate(BuildContext context, double extent, Widget child) {
    if (summary) return child;
    return FilterChipGridDecorator<VisibleRangeCandidateFilter, FilterGridItem<VisibleRangeCandidateFilter>>(
      gridItem: gridItem,
      extent: extent,
      // The selection badge is drawn below from plain values; the decorator's
      // own overlay would look a page-scoped `Selection` provider up, which the
      // pinch-zoom preview and the wallpaper page cannot satisfy.
      selectable: false,
      highlightable: true,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          if (selecting && selectable) _buildSelectionBadge(context, extent),
        ],
      ),
    );
  }

  /// The selection mark: a tinted corner and a check, or a hollow circle while
  /// the page is selecting. It mirrors the album grid's overlay without
  /// depending on its providers.
  Widget _buildSelectionBadge(BuildContext context, double extent) {
    final colors = Theme.of(context).colorScheme;
    final iconSize = CoveredFilterChip.detailIconSize(extent) * 1.6;
    return IgnorePointer(
      child: AnimatedContainer(
        alignment: AlignmentDirectional.topEnd,
        padding: EdgeInsets.all(extent / 24),
        duration: ADurations.chipDecorationAnimation,
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: .6) : Colors.transparent,
          borderRadius: BorderRadius.all(CoveredFilterChip.radius(extent)),
        ),
        child: AnimatedSwitcher(
          duration: ADurations.chipDecorationAnimation,
          child: selected
              ? Icon(AIcons.selected, key: const ValueKey(true), size: iconSize, color: colors.onPrimary)
              : DecoratedBox(
                  key: const ValueKey(false),
                  decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                  child: Icon(AIcons.unselected, size: iconSize, color: Colors.white),
                ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, double extent) {
    final theme = context.read<FilterListDetailsThemeData>();
    final label = labelOverride.isNotEmpty ? labelOverride : visibleRangeCandidateLabel(context, candidate);
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _decorate(
            context,
            extent,
            _buildChip(context, extent, showText: false),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, maxLines: theme.titleMaxLines, overflow: TextOverflow.ellipsis, style: theme.titleStyle),
                  const SizedBox(height: 2),
                  _buildDetails(context, extent, theme.captionStyle.color),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, double extent, {required bool showText}) {
    final textScaler = MediaQuery.textScalerOf(context);
    final infoHeight = showText ? CoveredFilterChip.infoHeight(extent: extent, textScaler: textScaler, showText: true) : 0.0;
    final inactiveRule = candidate.rule != null && !candidate.active;
    final displayFilter = labelOverride.isEmpty
        ? gridItem.filter
        : VisibleRangeCandidateFilter(candidate, summary: summary, labelOverride: labelOverride);
    return Opacity(
      opacity: inactiveRule ? .62 : 1,
      child: AvesFilterChip(
        filter: displayFilter,
        // The state icon in the details row replaces the kind icon: a candidate
        // is identified by its name, and its kind is already the section.
        showLeading: false,
        showText: showText,
        allowGenericIcon: false,
        useFilterColor: false,
        padding: min(4.0, extent / 32),
        decoration: AvesFilterDecoration(
          radius: CoveredFilterChip.radius(extent),
          widget: Padding(
            padding: EdgeInsets.only(bottom: infoHeight),
            child: _buildCover(context, extent),
          ),
        ),
        details: showText ? _buildDetails(context, extent, Theme.of(context).colorScheme.onSurfaceVariant) : null,
        heroType: HeroType.never,
        onTap: onTap != null ? (_) => onTap!.call() : null,
        onRemove: summary && onRemove != null ? (_) => onRemove!.call() : null,
        onLongPress: onLongPress != null ? (_, _, _) => onLongPress!() : null,
      ),
    );
  }

  Widget _buildCover(BuildContext context, double extent) {
    final cover = stats?.cover;
    if (cover != null) {
      return ThumbnailImage(
        entry: cover,
        extent: extent,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    }
    final brightness = Theme.of(context).brightness;
    final color = ThumbnailImage.computeLoadingBackgroundColor(candidate.id.hashCode, brightness);
    // One neutral placeholder for every candidate without a usable cover, so an
    // empty group never looks like a per-kind illustration.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: .72)],
        ),
      ),
      child: Center(
        child: Icon(
          AIcons.imageNotSupported,
          size: min(extent * .32, 44),
          color: brightness == Brightness.light ? Colors.black54 : Colors.white70,
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, double extent, Color? color) {
    final colors = Theme.of(context).colorScheme;
    final count = stats?.count;
    final countText = count != null ? settings.avesLocale.decimalNumberFormat().format(count) : null;
    final iconSize = CoveredFilterChip.detailIconSize(extent);
    final textStyle = TextStyle(
      color: color ?? colors.onSurfaceVariant,
      fontSize: CoveredFilterChip.detailFontSize(extent),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showStateIcon) ...[
          Icon(
            candidate.active ? AIcons.checked : AIcons.visibleRangeInactive,
            size: iconSize,
            color: candidate.active ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
        ],
        if (countText != null)
          Flexible(
            child: Text(
              countText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
      ],
    );
  }
}
