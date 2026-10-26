import 'dart:math';

import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Responsive multi-select grid of pin targets.
///
/// A target is a badge (its number) plus its name, so a row of wallpaper groups
/// stays readable on a phone. The data comes from the caller, which means
/// wallpaper groups appear here as soon as they are registered, with no layout
/// change.
class VisibleRangeTargetGrid extends StatelessWidget {
  /// Target cell width used to derive the column count. Wide enough for a badge
  /// and a few characters of the name.
  static const double targetCellWidth = 104;

  static int columnCountFor(double width) => max(1, (width / targetCellWidth).floor());

  final List<VisibleRangePinTarget> targets;
  final Set<String> selectedRangeIds;
  final ValueChanged<VisibleRangePinTarget> onToggle;

  const new({
    super.key,
    required this.targets,
    required this.selectedRangeIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnCountFor(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: targets.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final target = targets[index];
            return _TargetCell(
              key: ValueKey('pin-target-${target.rangeId}'),
              target: target,
              selected: selectedRangeIds.contains(target.rangeId),
              onTap: target.locked ? null : () => onToggle(target),
            );
          },
        );
      },
    );
  }
}

class _TargetCell extends StatelessWidget {
  final VisibleRangePinTarget target;
  final bool selected;
  final VoidCallback? onTap;

  const new({
    super.key,
    required this.target,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locked = target.locked;
    final background = locked
        ? colors.surfaceContainerHighest.withValues(alpha: .4)
        : selected
            ? colors.primaryContainer
            : colors.surfaceContainerHighest;
    final foreground = locked ? colors.onSurface.withValues(alpha: .38) : selected ? colors.onPrimaryContainer : colors.onSurfaceVariant;
    final label = target.isGallery ? context.l10n.visibleRangePinTargetGallery : target.name;

    return Material(
      color: background,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: BorderSide(
          color: selected && !locked ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _NumberBadge(number: target.number, color: foreground),
                  const Spacer(),
                  if (locked)
                    Icon(AIcons.locked, size: 16, color: foreground)
                  else if (selected)
                    Icon(Icons.check_circle, size: 16, color: colors.primary),
                ],
              ),
              const Spacer(),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  final int number;
  final Color color;

  const new({required this.number, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: .6)),
      ),
      child: Text(
        '$number',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
