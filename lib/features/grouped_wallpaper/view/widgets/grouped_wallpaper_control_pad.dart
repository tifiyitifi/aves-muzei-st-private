import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_control_pad_layout.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_pad_config.dart';
import 'package:aves/theme/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The view page's floating control pad: a draggable grid with a visible grip.
///
/// The page hands in the shape and one widget per cell, so the pad only owns
/// what is the same for every control: the handle, the panel background, the
/// drag and the remembered place. It positions itself, so it must be a direct
/// child of the page's `Stack`.
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

  /// The grid the cells are laid out in.
  final GroupedWallpaperPadShape shape;

  /// One widget per cell, row-major, empty cells as null.
  final List<Widget?> cells;

  const new({
    super.key,
    required this.position,
    required this.viewportSize,
    required this.safeInsets,
    required this.onMoved,
    required this.visible,
    required this.shape,
    required this.cells,
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

  Size get _extent => groupedWallpaperControlPadExtentFor(columns: widget.shape.columns, rows: widget.shape.rows);

  void _onPanStart(DragStartDetails _) {
    _dragTopLeft = groupedWallpaperControlPadTopLeft(position: widget.position.value, viewportSize: widget.viewportSize, safeInsets: widget.safeInsets, extent: _extent);
    _moved = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final start = _dragTopLeft;
    if (start == null) return;
    final next = start + details.delta;
    _dragTopLeft = next;
    final clamped = groupedWallpaperControlPadPositionFrom(topLeft: next, viewportSize: widget.viewportSize, safeInsets: widget.safeInsets, extent: _extent);
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
        final extent = _extent;
        final topLeft = groupedWallpaperControlPadTopLeft(position: position, viewportSize: widget.viewportSize, safeInsets: widget.safeInsets, extent: extent);
        return Positioned(
          left: topLeft.dx,
          top: topLeft.dy,
          width: extent.width,
          height: extent.height,
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
                    // The whole panel is the drag surface: the handle is the
                    // obvious place to grab, not the only one that works.
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanCancel: _onPanCancel,
                    onPanEnd: _onPanEnd,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0x73000000),
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _DragHandle(),
                          Expanded(child: _grid()),
                        ],
                      ),
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

  Widget _grid() {
    final cells = widget.cells;
    final columns = widget.shape.columns;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < widget.shape.rows; row++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var column = 0; column < columns; column++)
                SizedBox(
                  width: groupedWallpaperControlPadCell,
                  height: groupedWallpaperControlPadCell,
                  child: row * columns + column < cells.length ? cells[row * columns + column] : null,
                ),
            ],
          ),
      ],
    );
  }
}

/// The visible grip on the pad's left edge.
class _DragHandle extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Container(
    width: groupedWallpaperControlPadHandleWidth,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
    ),
    child: const Center(
      // The symbol is horizontal; a quarter turn makes a vertical grip.
      child: RotatedBox(
        quarterTurns: 1,
        child: Icon(AIcons.dragHandle, size: 18, color: Colors.white54),
      ),
    ),
  );
}
