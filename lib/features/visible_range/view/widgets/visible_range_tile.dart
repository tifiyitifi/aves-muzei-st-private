import 'dart:math';

import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
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
/// It is the album page's chip, not a parallel card design: [AvesFilterChip]
/// supplies the radius, padding, typography and leading icon, while the cover
/// and count come from the feature's stats service because candidates are filter
/// sets rather than covered filters. [FilterChipGridDecorator] supplies the
/// album page's selection and highlight overlays.
class VisibleRangeTile extends StatelessWidget {
  final FilterGridItem<VisibleRangeCandidateFilter> gridItem;
  final VisibleRangeCandidateStats? stats;
  final TileLayout tileLayout;
  final Size tileSize;
  final bool summary;
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
    this.onTap,
    this.onRemove,
    this.onLongPress,
  });

  VisibleRangeCandidate get candidate => gridItem.filter.candidate;

  @override
  Widget build(BuildContext context) {
    final extent = tileLayout == TileLayout.grid ? tileSize.width : tileSize.height;
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
      selectable: true,
      highlightable: true,
      child: child,
    );
  }

  Widget _buildList(BuildContext context, double extent) {
    final theme = context.read<FilterListDetailsThemeData>();
    final l10n = context.l10n;
    final label = visibleRangeCandidateLabel(context, candidate);
    final filtersLabel = visibleRangeFilterLabels(context, candidate.filters);
    final count = stats?.count;
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
                  if (filtersLabel.isNotEmpty && filtersLabel != label) ...[
                    const SizedBox(height: 2),
                    Text(filtersLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.captionStyle),
                  ],
                  if (count != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (candidate.active || candidate.rule != null) ...[
                          Icon(
                            candidate.active ? AIcons.checked : AIcons.visibleRangeInactive,
                            size: theme.captionIconTheme.size,
                            color: candidate.active ? Theme.of(context).colorScheme.primary : theme.captionStyle.color,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(l10n.visibleRangeCount(count), style: theme.captionStyle),
                      ],
                    ),
                  ],
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
    final count = stats?.count;
    final countText = count != null ? settings.avesLocale.decimalNumberFormat().format(count) : null;
    final inactiveRule = candidate.rule != null && !candidate.active;
    return Opacity(
      opacity: inactiveRule ? .62 : 1,
      child: AvesFilterChip(
        filter: gridItem.filter,
        showLeading: true,
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
        details: showText ? _buildDetails(context, extent, countText) : null,
        heroType: HeroType.never,
        onTap: (_) => onTap?.call(),
        onRemove: summary ? (_) => onRemove?.call() : null,
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
          _kindIcon,
          size: min(extent * .32, 44),
          color: brightness == Brightness.light ? Colors.black54 : Colors.white70,
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, double extent, String? countText) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final iconSize = CoveredFilterChip.detailIconSize(extent);
    final fontSize = CoveredFilterChip.detailFontSize(extent);
    final showIcon = candidate.active || candidate.rule != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) ...[
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
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: fontSize),
            ),
          ),
      ],
    );
  }

  IconData get _kindIcon => candidate.isUnrestricted
      ? AIcons.filterOff
      : switch (candidate.kind) {
          VisibleRangeCandidateKind.base => AIcons.visibleRangeBase,
          VisibleRangeCandidateKind.restriction => AIcons.visibleRangeRestriction,
          VisibleRangeCandidateKind.supplement => AIcons.visibleRangeSupplement,
        };
}
