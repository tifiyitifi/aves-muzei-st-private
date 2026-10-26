import 'package:aves/theme/durations.dart';
import 'package:aves/theme/icons.dart';
import 'package:material_ui/material_ui.dart';

/// A chip on the visible-range page.
///
/// It deliberately does not reuse `AvesFilterChip`: a rule is a *set* of filters,
/// not one filter, so it has no single label, colour or cover. The shape, radius
/// and typography follow the album chip grid so the page still reads as a
/// collection surface.
class VisibleRangeChip extends StatelessWidget {
  final String label;
  final String? detail;
  final IconData? icon;
  final bool selected;
  final bool active;
  final bool locked;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;

  const new({
    super.key,
    required this.label,
    this.detail,
    this.icon,
    this.selected = false,
    this.active = true,
    this.locked = false,
    this.onTap,
    this.onLongPress,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = active && !locked;
    final foreground = enabled ? colors.onSurface : colors.onSurfaceVariant;
    final background = selected
        ? colors.secondaryContainer
        : active
            ? theme.cardColor
            : colors.surfaceContainerHighest.withValues(alpha: 0.4);
    final border = selected ? colors.secondary : colors.outlineVariant.withValues(alpha: 0.5);

    return AnimatedContainer(
      duration: ADurations.chipDecorationAnimation,
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: border, width: selected ? 2 : 1),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          decoration: active ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (locked) ...[
                  const SizedBox(width: 6),
                  Icon(AIcons.locked, size: 14, color: colors.onSurfaceVariant),
                ] else if (onRemove != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(AIcons.delete, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
