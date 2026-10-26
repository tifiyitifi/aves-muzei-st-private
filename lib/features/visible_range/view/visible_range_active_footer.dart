import 'dart:math';

import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves/widgets/common/thumbnail/image.dart';
import 'package:aves/widgets/filter_grids/common/covered_filter_chip.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

/// The "current visible range" footer.
///
/// The first item is always the gallery result: the range's own count and cover,
/// which tells what the current conditions produce before listing the conditions
/// themselves. The tappable conditions follow and cancel themselves when tapped.
/// The compact style is a wrap of album chips; the tile style is a wrap of tiles
/// sized like the grid above, so the footer does not shrink.
class VisibleRangeActiveFooter extends StatelessWidget {
  /// The gallery result is a read-only preview: it carries the range's filters
  /// but no condition that could be toggled or removed.
  static const _resultCandidate = VisibleRangeCandidate(
    id: 'gallery',
    kind: VisibleRangeCandidateKind.base,
    filters: {},
    labelKey: 'visibleRangeGallery',
    active: true,
  );

  final VisibleRange range;
  final VisibleRangeCandidate? activeBase;
  final List<VisibleRangeCandidate> activeRules;
  final VisibleRangeActiveStyle style;
  final VisibleRangeCandidateStats? resultStats;
  final VisibleRangeCandidateStats? Function(VisibleRangeCandidate candidate) statsFor;
  final double tileExtent;
  final VoidCallback onCancelBase;
  final ValueChanged<VisibleRangeCandidate> onCancelRule;
  final VoidCallback onAbout;

  const new({
    super.key,
    required this.range,
    required this.activeBase,
    required this.activeRules,
    required this.style,
    required this.resultStats,
    required this.statsFor,
    required this.tileExtent,
    required this.onCancelBase,
    required this.onCancelRule,
    required this.onAbout,
  });

  /// The active conditions, excluding the unrestricted base: the gallery chip
  /// already stands for "everything", so repeating it as a condition would show
  /// the same total twice.
  Iterable<VisibleRangeCandidate> get _all => [
        if (activeBase != null && !activeBase!.isUnrestricted) activeBase!,
        ...activeRules,
      ];

  bool _removable(VisibleRangeCandidate candidate) => !candidate.isUnrestricted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final restricted = range.isRestricted;
    final candidates = _all.toList();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The lamp marks what the range currently lights up, matching the
              // old scenario page instead of the previous eye icon.
              Icon(AIcons.visibleRangeActive, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.visibleRangeSectionCurrent, style: theme.textTheme.titleSmall)),
              Text(
                restricted ? l10n.visibleRangeRestricted : l10n.visibleRangeUnrestricted,
                style: theme.textTheme.labelLarge?.copyWith(color: restricted ? colors.error : colors.primary),
              ),
              IconButton(
                icon: const Icon(AIcons.info),
                tooltip: l10n.visibleRangeAbout,
                onPressed: onAbout,
              ),
            ],
          ),
          if (style == VisibleRangeActiveStyle.compactChips)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildResultChip(context),
                for (final candidate in candidates) _buildChip(context, candidate),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildResultTile(context),
                for (final candidate in candidates) _buildTile(context, candidate),
              ],
            ),
        ],
      ),
    );
  }

  Size _tileSize(BuildContext context) {
    // An unmeasured extent (first frame) would collapse the tiles, so keep a
    // sane minimum instead of rendering zero-sized items.
    final extent = max(tileExtent, AvesFilterChip.minChipHeight);
    final textScaler = MediaQuery.textScalerOf(context);
    return Size(extent, CoveredFilterChip.tileHeight(extent: extent, textScaler: textScaler, showText: true));
  }

  Widget _buildResultChip(BuildContext context) {
    final cover = resultStats?.cover;
    const iconSize = AvesFilterChip.iconSize;
    return AvesFilterChip(
      filter: VisibleRangeCandidateFilter(_resultCandidate, summary: true),
      showLeading: true,
      showText: true,
      allowGenericIcon: false,
      useFilterColor: false,
      leadingOverride: cover != null
          ? ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              child: SizedBox.square(
                dimension: iconSize,
                child: ThumbnailImage(
                  entry: cover,
                  extent: iconSize,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                ),
              ),
            )
          : const Icon(AIcons.image, size: iconSize),
      details: _buildCount(context),
      heroType: HeroType.never,
      // The result is a preview only: tapping and removing it do nothing.
      onTap: null,
      onRemove: null,
      onLongPress: null,
    );
  }

  Widget _buildResultTile(BuildContext context) {
    final size = _tileSize(context);
    return SizedBox.fromSize(
      size: size,
      child: VisibleRangeTile(
        gridItem: FilterGridItem(VisibleRangeCandidateFilter(_resultCandidate, summary: true), resultStats?.cover),
        stats: resultStats,
        tileLayout: TileLayout.grid,
        tileSize: size,
        summary: true,
        showStateIcon: false,
      ),
    );
  }

  Widget _buildTile(BuildContext context, VisibleRangeCandidate candidate) {
    final removable = _removable(candidate);
    final size = _tileSize(context);
    return SizedBox.fromSize(
      size: size,
      child: VisibleRangeTile(
        gridItem: FilterGridItem(VisibleRangeCandidateFilter(candidate, summary: true), statsFor(candidate)?.cover),
        stats: statsFor(candidate),
        tileLayout: TileLayout.grid,
        tileSize: size,
        summary: true,
        onTap: removable ? () => _cancel(candidate) : null,
        onRemove: removable ? () => _cancel(candidate) : null,
      ),
    );
  }

  Widget _buildChip(BuildContext context, VisibleRangeCandidate candidate) {
    final removable = _removable(candidate);
    return AvesFilterChip(
      filter: VisibleRangeCandidateFilter(candidate, summary: true),
      showLeading: true,
      showText: true,
      allowGenericIcon: false,
      useFilterColor: false,
      details: _buildCount(context, candidate: candidate),
      heroType: HeroType.never,
      onTap: removable ? (_) => _cancel(candidate) : null,
      onRemove: removable ? (_) => _cancel(candidate) : null,
      onLongPress: null,
    );
  }

  Widget? _buildCount(BuildContext context, {VisibleRangeCandidate? candidate}) {
    final count = candidate != null ? statsFor(candidate)?.count : resultStats?.count;
    if (count == null) return null;
    return Text(
      settings.avesLocale.decimalNumberFormat().format(count),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  void _cancel(VisibleRangeCandidate candidate) {
    if (candidate.isUnrestricted) return;
    if (candidate.rule != null) {
      onCancelRule(candidate);
    } else {
      onCancelBase();
    }
  }
}
