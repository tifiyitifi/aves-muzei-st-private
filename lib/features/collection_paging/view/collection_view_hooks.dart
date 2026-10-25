import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// What a borrowed collection surface may do on behalf of its opener.
///
/// Aves' collection and album pages normally belong to the library: their
/// filters are the user's, their tiles open the viewer, and their floating
/// action button acts on the whole library. A task that borrows those pages
/// (the wallpaper source picker) needs them to look and navigate exactly like
/// the real ones while changing only what the task owns: an implicit
/// constraint, the confirm button, and what a tap means.
///
/// The hooks live above the pages that read them, so a route pushed from a
/// hooked page inherits the same task without any page passing state down.
abstract interface class CollectionViewHooks {
  /// Constraints a page must apply on top of the filters it was opened with.
  Set<CollectionFilter?>? augmentFilters(Set<CollectionFilter?>? filters);

  /// Keeps a view's filter set valid after the user edits it.
  Set<CollectionFilter> normalizeFilters(Set<CollectionFilter> filters);

  /// A view was just opened on [collection].
  ///
  /// A task that remembers a choice per view resets it here: the new view is a
  /// new question, even when it shows the same filters.
  void onViewOpened(CollectionLens collection);

  /// The floating action button the view should show, or null for the default.
  Widget? buildFab(BuildContext context, CollectionLens collection);

  /// Handles a tile tap; true when the task consumed it.
  bool onEntryTap(BuildContext context, CollectionLens collection, AvesEntry entry);

  /// The entry the task currently has picked, when it picks one entry.
  ///
  /// Tiles listen to it to draw the picked state. Null when the task does not
  /// pick entries, so the grid stays untouched.
  ValueListenable<int?>? get pickedEntryId;

  /// The set the media-set destination opens inside this task, when the task
  /// owns one.
  ///
  /// The bottom bar normally reopens the app-wide media-set slot; a borrowed
  /// view must not follow it out of the task. Null leaves the normal behaviour.
  Set<CollectionFilter>? get mediaSetFilters;

  /// Whether the double-back-to-exit handler must stand down.
  ///
  /// A borrowed view is not the app's root: backing out of it returns to the
  /// caller instead of exiting.
  bool get suppressDoubleBack;

  /// Whether the view only returns a choice to its opener.
  bool get isPicking;

  /// Whether filter actions that mutate the library are available.
  bool get allowFilterMutation;
}

/// Provides [CollectionViewHooks] to the pages below it.
class CollectionViewHooksScope extends InheritedWidget {
  final CollectionViewHooks hooks;

  const new({
    super.key,
    required this.hooks,
    required super.child,
  });

  /// The hooks, registering a dependency so the reader rebuilds if they change.
  static CollectionViewHooks? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CollectionViewHooksScope>()?.hooks;

  /// The hooks without registering a dependency.
  ///
  /// Used where the hooks are read once, such as a page's `initState`, and by
  /// callbacks that must not subscribe during a gesture.
  static CollectionViewHooks? read(BuildContext context) => context.getInheritedWidgetOfExactType<CollectionViewHooksScope>()?.hooks;

  @override
  bool updateShouldNotify(CollectionViewHooksScope oldWidget) => hooks != oldWidget.hooks;
}
