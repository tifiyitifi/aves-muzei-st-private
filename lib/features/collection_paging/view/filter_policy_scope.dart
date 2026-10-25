import 'package:aves/model/filters/filters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Controls which of a view's filters the filter bar may show and drop.
///
/// A view can carry constraints that are part of its purpose rather than user
/// choices: the wallpaper-source picker is always a photo library, so its image
/// restriction must not appear as a chip (it would follow the user into the
/// album and search pages) and must survive every removal gesture. Views without
/// this scope keep the normal behaviour.
@immutable
class FilterPolicyScope extends InheritedWidget {
  /// Filters hidden from the filter bar.
  final Set<CollectionFilter> hidden;

  /// Filters no removal gesture may drop, including "clear filters".
  final Set<CollectionFilter> locked;

  const new({
    super.key,
    this.hidden = const {},
    this.locked = const {},
    required super.child,
  });

  static FilterPolicyScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<FilterPolicyScope>();

  bool isHidden(CollectionFilter filter) => hidden.contains(filter);

  bool isLocked(CollectionFilter filter) => locked.contains(filter);

  @override
  bool updateShouldNotify(FilterPolicyScope oldWidget) {
    return !setEquals(hidden, oldWidget.hidden) || !setEquals(locked, oldWidget.locked);
  }
}
