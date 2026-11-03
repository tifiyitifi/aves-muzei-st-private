import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_control_pad_layout.dart';
import 'package:material_ui/material_ui.dart';

/// The view page's floating control pad: a draggable, left-aligned 3/2/1 stack.
///
/// The rows are handed in by the page, so the pad only owns what is the same for
/// every control: the bracket silhouette, the drag and the remembered place. It
/// positions itself, so it must be a direct child of the page's `Stack`.
///
/// Dragging writes the page's [position] notifier and nothing else: the builder
/// below rebuilds this subtree alone, which is why moving the pad never rebuilds
/// the photo or re-reads the wallpaper state. [onMoved] fires once at the end of
/// a drag, so the place is persisted once instead of every frame.
class GroupedWallpaperControlPad extends StatefulWidget {
  /// The resting place, as a fraction of the free space inside the safe area.
  final ValueNotifier<GroupedWallpaperControlPadPosition> position;

  /// The page's size, used to clamp the pad inside it.
  final Size viewportSize;

  /// The safe-area insets the pad stays clear of.
  final EdgeInsets safeInsets;

  /// Called when a drag ends, with the place to remember.
  final ValueChanged<GroupedWallpaperControlPadPosition> onMoved;

  /// Whether the chrome is on. The pad fades with it, like the info panel.
  final bool visible;

  /// The three top cells, left-aligned: previous photo, next photo, menu.
  final Widget topRow;

  /// The two middle cells, left-aligned: group up, group down.
  final Widget middleRow;

  /// The single bottom cell: delete.
  final Widget bottomRow;

  const new({
    super.key,
    required this.position,
    required this.viewportSize,
    required this.safeInsets,
    required this.onMoved,
    required this.visible,
    required this.topRow,
    required this.middleRow,
    required this.bottomRow,
  });

  @override
  State<GroupedWallpaperControlPad> createState() => _GroupedWallpaperControlPadState();
}

class _GroupedWallpaperControlPadState extends State<GroupedWallpaperControlPad> {
  /// The pad's top-left at the start of the drag, or null when idle.
  ///
  /// Accumulating the pointer's deltas here (instead of re-reading the notifier)
  /// keeps the drag smooth even though the notifier is clamped: a pointer that
  /// leaves the screen and comes back resumes from the edge it was pinned to.
  Offset? _dragTopLeft;

  /// Whether this drag moved the pad, so a tap that starts a drag does not write
  /// an unchanged value.
  bool _moved = false;

  void _onPanStart(DragStartDetails _) {
    _dragTopLeft = groupedWallpaperControlPadTopLeft(position: widget.position.value, viewportSize: widget.viewportSize, safeInsets: widget.safeInsets);
    _moved = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final start = _dragTopLeft;
    if (start == null) return;
    final next = start + details.delta;
    _dragTopLeft = next;
    final clamped = groupedWallpaperControlPadPositionFrom(topLeft: next, viewportSize: widget.viewportSize, safeInsets: widget.safeInsets);
    if (clamped == widget.position.value) return;
    widget.position.value = clamped;
    _moved = true;
  }

  void _onPanEnd(DragEndDetails _) => _settle();

  void _onPanCancel() => _settle();

  /// Keeps what the drag reached, whichever way it ended.
  void _settle() {
    if (_moved) widget.onMoved(widget.position.value);
    _dragTopLeft = null;
    _moved = false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GroupedWallpaperControlPadPosition>(
      valueListenable: widget.position,
      builder: (context, position, _) {
        final topLeft = groupedWallpaperControlPadTopLeft(position: position, viewportSize: widget.viewportSize, safeInsets: widget.safeInsets);
        return Positioned(
          left: topLeft.dx,
          top: topLeft.dy,
          width: groupedWallpaperControlPadExtent,
          height: groupedWallpaperControlPadExtent,
          child: IgnorePointer(
            ignoring: !widget.visible,
            child: AnimatedOpacity(
              opacity: widget.visible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: RepaintBoundary(
                // The scaffold's material is below the pad's own tint, so ink
                // needs a transparent material of its own to be visible.
                child: Material(
                  type: MaterialType.transparency,
                  child: GestureDetector(
                    // Deferring to the children keeps the empty part of the
                    // 3x3 box transparent to the photo's own tap.
                    behavior: HitTestBehavior.deferToChild,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanCancel: _onPanCancel,
                    onPanEnd: _onPanEnd,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row(
                          widget.topRow,
                          cells: 3,
                          radius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                        ),
                        _row(widget.middleRow, cells: 2, radius: BorderRadius.zero),
                        _row(
                          widget.bottomRow,
                          cells: 1,
                          radius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// One step of the bracket: a tinted band exactly as wide as its cells.
  ///
  /// The bands are stacked without gaps, so the free corner stays transparent and
  /// the silhouette follows the 3/2/1 rows instead of reading as a square.
  Widget _row(Widget child, {required int cells, required BorderRadius radius}) => SizedBox(
    width: cells * groupedWallpaperControlPadCell,
    height: groupedWallpaperControlPadCell,
    child: DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), borderRadius: radius),
      child: child,
    ),
  );
}
