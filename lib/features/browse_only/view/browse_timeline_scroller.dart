import 'package:aves/features/browse_only/model/browse_scroll_map.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/basic/draggable_scrollbar/scrollbar.dart';
import 'package:aves/widgets/common/identity/scroll_thumb.dart';
import 'package:material_ui/material_ui.dart';

/// How many months a timeline needs before the drag scrollbar is worth showing.
///
/// A short list is one flick away from either end, and the thumb would cover
/// content without saving a gesture.
const _minMonthsForScroller = 4;

/// The right-edge drag handle of a browse timeline, with the month under the
/// finger on a pill.
///
/// It is a cheap part of the surface by construction: the month starts come from
/// [BrowseScrollMap] (arithmetic over the item list, not a walk of the rows), the
/// drag jumps the existing controller, and the label is formatted once per
/// rebuild. Nothing is read from the media store to move it.
class BrowseTimelineScroller extends StatelessWidget {
  final ScrollController controller;
  final BrowseScrollMap map;
  final Widget child;

  const new({
    super.key,
    required this.controller,
    required this.map,
    required this.child,
  });

  /// Whether this timeline is long enough to carry the handle.
  static bool appliesTo(BrowseScrollMap map) => map.months.length >= _minMonthsForScroller && map.totalExtent > 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pillColor = theme.colorScheme.primary;
    final onPillColor = theme.colorScheme.onPrimary;

    Widget pill(String text, TextStyle? style) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: style?.copyWith(color: onPillColor),
      ),
    );

    String monthLabel(BrowseScrollMonth? month) => month == null ? '' : settings.avesLocale.yMMMM(DateTime(month.year, month.month));

    return DraggableScrollbar(
      backgroundColor: pillColor,
      scrollThumbSize: AvesScrollThumb.thumbSize,
      scrollThumbBuilder: AvesScrollThumb.builder(
        height: AvesScrollThumb.thumbHeight,
        backgroundColor: pillColor,
      ),
      controller: controller,
      // A drag lands on a month: scrubbing a gallery is "go to March", not
      // "go 12 pixels into March".
      dragOffsetSnapper: (scrollOffset, offsetIncrement) => map.snap(scrollOffset),
      scrollCrumbsBuilder: () => {
        for (final entry in map.monthFractions().entries) entry.key: monthLabel(entry.value),
      },
      labelTextBuilder: (offsetY) => pill(monthLabel(map.monthAt(offsetY)), theme.textTheme.bodyMedium),
      crumbTextBuilder: (label) => pill(label, theme.textTheme.labelSmall),
      child: child,
    );
  }
}
