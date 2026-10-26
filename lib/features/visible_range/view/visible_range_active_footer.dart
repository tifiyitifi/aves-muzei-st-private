import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

/// The "current visible range" footer.
///
/// Active conditions are listed as tappable items, so removing one is the same
/// gesture as reading it. The compact style is a wrap of album chips; the tile
/// style is a wrap of thumbnail tiles. Both are chosen in the layout dialog.
class VisibleRangeActiveFooter extends StatelessWidget {
  final VisibleRange range;
  final VisibleRangeCandidate? activeBase;
  final List<VisibleRangeCandidate> activeRules;
  final VisibleRangeActiveStyle style;
  final VisibleRangeCandidateStats? Function(VisibleRangeCandidate candidate) statsFor;
  final int? totalCount;
  final VoidCallback onCancelBase;
  final ValueChanged<VisibleRangeCandidate> onCancelRule;
  final VoidCallback onAbout;

  const new({
    super.key,
    required this.range,
    required this.activeBase,
    required this.activeRules,
    required this.style,
    required this.statsFor,
    required this.totalCount,
    required this.onCancelBase,
    required this.onCancelRule,
    required this.onAbout,
  });

  Iterable<VisibleRangeCandidate> get _all => [
        ?activeBase,
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
              Icon(AIcons.visibleRangeActive, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.visibleRangeSectionCurrent, style: theme.textTheme.titleSmall)),
              Text(
                restricted ? l10n.visibleRangeRestricted : l10n.visibleRangeUnrestricted,
                style: theme.textTheme.labelLarge?.copyWith(color: restricted ? colors.error : colors.primary),
              ),
              const SizedBox(width: 8),
              if (totalCount != null) Text(l10n.visibleRangeCount(totalCount!), style: theme.textTheme.bodySmall),
              IconButton(
                icon: const Icon(AIcons.info),
                tooltip: l10n.visibleRangeAbout,
                onPressed: onAbout,
              ),
            ],
          ),
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 8),
              child: Text(l10n.visibleRangeNoCandidates, style: theme.textTheme.bodySmall),
            )
          else if (style == VisibleRangeActiveStyle.compactChips)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final candidate in candidates) _buildChip(context, candidate),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final candidate in candidates)
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: VisibleRangeTile(
                      gridItem: FilterGridItem(VisibleRangeCandidateFilter(candidate, summary: true), statsFor(candidate)?.cover),
                      stats: statsFor(candidate),
                      tileLayout: TileLayout.grid,
                      tileSize: const Size(96, 96),
                      summary: true,
                      onTap: _removable(candidate) ? () => _cancel(candidate) : null,
                      onRemove: _removable(candidate) ? () => _cancel(candidate) : null,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, VisibleRangeCandidate candidate) {
    final stats = statsFor(candidate);
    final count = stats?.count;
    final removable = _removable(candidate);
    return AvesFilterChip(
      filter: VisibleRangeCandidateFilter(candidate, summary: true),
      showLeading: true,
      showText: true,
      allowGenericIcon: false,
      useFilterColor: false,
      maxWidth: MediaQuery.sizeOf(context).width - 32,
      details: count == null ? null : Text(context.l10n.visibleRangeCount(count)),
      heroType: HeroType.never,
      onTap: removable ? (_) => _cancel(candidate) : null,
      onRemove: removable ? (_) => _cancel(candidate) : null,
      onLongPress: null,
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
