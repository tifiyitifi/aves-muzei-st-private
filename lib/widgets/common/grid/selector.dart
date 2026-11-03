import 'dart:async';
import 'dart:math';

import 'package:aves/features/selection_xor/selection_xor.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/basic/gestures/gesture_detector.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/extensions/media_query.dart';
import 'package:aves/widgets/common/grid/sections/list_layout.dart';
import 'package:aves_utils/aves_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class GridSelectionGestureDetector<T> extends StatefulWidget {
  final GlobalKey scrollableKey;
  final bool selectable;
  final List<T> items;
  final ScrollController scrollController;
  final ValueNotifier<double> appBarHeightNotifier;

  /// Extent of a fixed header shown between the app bar and the sections.
  ///
  /// The layout space starts below it, so the hit test has to subtract it the
  /// same way it subtracts the app bar. The header scrolls with the content, so
  /// it only offsets the position and never the auto-scroll insets.
  final ValueListenable<double>? headerHeight;

  /// Whether [item] belongs to the same selection as [selected].
  ///
  /// A page can show several grids in one scroll view (the wallpaper page's
  /// groups and conditions); this keeps a range from crossing into the other
  /// grid. Evaluated at press time against the live selection, so the page does
  /// not have to rebuild the grid to change the allowed rows.
  final bool Function(T item, Set<T> selected)? sameSelectionScope;

  final Widget child;

  const new({
    super.key,
    required this.scrollableKey,
    this.selectable = true,
    required this.items,
    required this.scrollController,
    required this.appBarHeightNotifier,
    this.headerHeight,
    this.sameSelectionScope,
    required this.child,
  });

  @override
  State<GridSelectionGestureDetector<T>> createState() => _GridSelectionGestureDetectorState<T>();
}

class _GridSelectionGestureDetectorState<T> extends State<GridSelectionGestureDetector<T>> {
  bool _pressing = false, _selecting = false;
  late int _fromIndex, _lastToIndex;
  late Offset _localPosition;
  late EdgeInsets _scrollableInsets;
  late double _scrollSpeedFactor;

  /// The rows the current press may range over, captured when it started.
  ///
  /// The page scopes a selection to one grid; keeping the narrowed list for the
  /// whole gesture is what stops a drag from painting rows of the other grid.
  List<T> _rangeItems = const [];

  Timer? _selectionUpdateTimer;
  Timer? _scrollMonitoringTimer;
  var _isScrolling = false;

  List<T> get items => widget.items;

  ScrollController get scrollController => widget.scrollController;

  double get appBarHeight => widget.appBarHeightNotifier.value;

  double get headerHeight => widget.headerHeight?.value ?? 0;

  double get scrollableWidth {
    final scrollableContext = widget.scrollableKey.currentContext!;
    final scrollableBox = scrollableContext.findRenderObject() as RenderBox;
    // not the same as `MediaQuery.size.width`, because of screen insets/padding
    return scrollableBox.size.width;
  }

  static const double _scrollEdgeRatio = .15;
  static const double _scrollMaxPixelPerSecond = 600.0;
  static const Duration _scrollUpdateInterval = Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    _registerWidget(widget);
  }

  @override
  void didUpdateWidget(covariant GridSelectionGestureDetector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _unregisterWidget(oldWidget);
    _registerWidget(widget);
  }

  @override
  void dispose() {
    _unregisterWidget(widget);
    _stopScrollMonitoringTimer();
    super.dispose();
  }

  void _registerWidget(GridSelectionGestureDetector<T> widget) {
    widget.scrollController.addListener(_onScrollChanged);
  }

  void _unregisterWidget(GridSelectionGestureDetector<T> widget) {
    widget.scrollController.removeListener(_onScrollChanged);
  }

  @override
  Widget build(BuildContext context) {
    final selectable = widget.selectable;
    return AGestureDetector(
      onLongPressStart: selectable
          ? (details) {
              if (_isScrolling) return;

              final fromItem = _getItemAt(details.localPosition);
              if (fromItem == null) return;

              final selection = context.read<Selection<T>>();
              // The layout resolves the pressed row from its position, not from
              // the caller's selectable list, so a row the page scoped out (a
              // summary, another grid's cards) must not start a selection.
              final scopedItems = _scopeItems(fromItem, selection);
              if (!scopedItems.any((item) => selection.isSameItem(item, fromItem))) return;
              Feedback.forLongPress(context);
              if (selection.isSelecting) {
                // A long press while selecting flips the interval from the
                // anchor to the pressed row. This and the drag below stay two
                // independent contributions: the flip settles the rows in
                // between, then painting continues from the pressed row, where
                // `_selecting` is again what decides between adding and erasing.
                selection.rangeXorTo(scopedItems, fromItem);
              } else {
                selection.toggleSelection(fromItem);
              }
              _selecting = selection.isSelected([fromItem]);
              _rangeItems = scopedItems;
              _fromIndex = scopedItems.indexOf(fromItem);
              _lastToIndex = _fromIndex;
              _scrollableInsets = EdgeInsets.only(
                top: appBarHeight,
                bottom: context.read<MediaQueryData>().safeBottomPadding,
              );
              _scrollSpeedFactor = 0;
              _pressing = true;
            }
          : null,
      onLongPressMoveUpdate: selectable
          ? (details) {
              if (!_pressing) return;
              _localPosition = details.localPosition;
              _onLongPressUpdate();
            }
          : null,
      onLongPressEnd: selectable
          ? (details) {
              if (!_pressing) return;
              _setScrollSpeed(0);
              _pressing = false;
            }
          : null,
      onTapUp: selectable && context.select<Selection<T>, bool>((selection) => selection.isSelecting)
          ? (details) {
              if (_isScrolling) return;

              final item = _getItemAt(details.localPosition);
              if (item == null) return;

              final selection = context.read<Selection<T>>();
              if (!_scopeItems(item, selection).any((candidate) => selection.isSameItem(candidate, item))) return;
              selection.toggleSelection(item);
            }
          : null,
      longPressTimeout: settings.longPressTimeout,
      child: widget.child,
    );
  }

  /// The rows a press on [pressed] may select, in display order.
  ///
  /// Without a scope seam this is every selectable item. With one, the page
  /// narrows it to the grid the press belongs to, so neither the flip nor the
  /// drag can reach the other grid's rows.
  List<T> _scopeItems(T pressed, Selection<T> selection) {
    final accept = widget.sameSelectionScope;
    if (accept == null) return items;
    final selected = selection.selectedItems;
    return items.where((item) => accept(item, selected)).toList();
  }

  void _onScrollChanged() {
    _isScrolling = true;
    _stopScrollMonitoringTimer();
    _scrollMonitoringTimer = Timer(settings.longPressTimeout + const Duration(milliseconds: 150), () {
      _isScrolling = false;
    });
  }

  void _stopScrollMonitoringTimer() => _scrollMonitoringTimer?.cancel();

  void _onLongPressUpdate() {
    if (!scrollController.hasClients) return;

    final dy = _localPosition.dy;

    final height = scrollController.position.viewportDimension;
    final top = dy < height / 2;

    final distanceToEdge = max(0, top ? dy - _scrollableInsets.top : height - dy - _scrollableInsets.bottom);
    final threshold = height * _scrollEdgeRatio;
    if (distanceToEdge < threshold) {
      _setScrollSpeed((top ? -1 : 1) * roundToPrecision((threshold - distanceToEdge) / threshold, decimals: 1));
    } else {
      _setScrollSpeed(0);
    }

    final toItem = _getItemAt(_localPosition);
    if (toItem != null) {
      _toggleSelectionToIndex(_rangeItems.indexOf(toItem));
    }
  }

  void _setScrollSpeed(double speedFactor) {
    if (speedFactor == _scrollSpeedFactor) return;
    _scrollSpeedFactor = speedFactor;
    _selectionUpdateTimer?.cancel();

    final current = scrollController.offset;
    if (speedFactor == 0) {
      scrollController.jumpTo(current);
      return;
    }

    final target = speedFactor > 0 ? scrollController.position.maxScrollExtent : .0;
    if (target != current) {
      final distance = target - current;
      final millis = distance * 1000 / _scrollMaxPixelPerSecond / speedFactor;
      scrollController.animateTo(
        target,
        duration: Duration(milliseconds: millis.round()),
        curve: Curves.linear,
      );
      // use a timer to update the selection, because `onLongPressMoveUpdate`
      // is not called when the pointer stays still while the view is scrolling
      _selectionUpdateTimer = Timer.periodic(_scrollUpdateInterval, (_) => _onLongPressUpdate());
    }
  }

  T? _getItemAt(Offset localPosition) {
    // as of Flutter v1.22.5, `hitTest` on the `ScrollView` render object works fine when it is static,
    // but when it is scrolling (through controller animation), result is incomplete and children are missing,
    // so we use custom layout computation instead to find the item.
    final offset = Offset(0, scrollController.offset - appBarHeight - headerHeight) + localPosition;
    final sectionedListLayout = context.read<SectionedListLayout<T>>();
    return sectionedListLayout.getItemAt(context.isRtl ? Offset(scrollableWidth - offset.dx, offset.dy) : offset);
  }

  void _toggleSelectionToIndex(int toIndex) {
    if (toIndex == -1) return;

    Iterable<T> getRange(int start, int end) => start < end && 0 <= start && end <= _rangeItems.length ? _rangeItems.getRange(start, end) : {};
    final selection = context.read<Selection<T>>();
    void addRange(int start, int end) => selection.addToSelection(getRange(start, end));
    void removeRange(int start, int end) => selection.removeFromSelection(getRange(start, end));

    if (_selecting) {
      if (toIndex <= _fromIndex) {
        if (toIndex < _lastToIndex) {
          addRange(toIndex, min(_fromIndex, _lastToIndex));
          if (_fromIndex < _lastToIndex) {
            removeRange(_fromIndex + 1, _lastToIndex + 1);
          }
        } else if (_lastToIndex < toIndex) {
          removeRange(_lastToIndex, toIndex);
        }
      } else if (_fromIndex < toIndex) {
        if (_lastToIndex < toIndex) {
          addRange(max(_fromIndex, _lastToIndex), toIndex + 1);
          if (_lastToIndex < _fromIndex) {
            removeRange(_lastToIndex, _fromIndex);
          }
        } else if (toIndex < _lastToIndex) {
          removeRange(toIndex + 1, _lastToIndex + 1);
        }
      }
      _lastToIndex = toIndex;
    } else {
      removeRange(min(_fromIndex, toIndex), max(_fromIndex, toIndex) + 1);
    }
  }
}
