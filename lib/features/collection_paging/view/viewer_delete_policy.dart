import 'package:aves/model/entry/entry.dart';
import 'package:flutter/widgets.dart';

/// Lets the opening task take part in the viewer's delete action.
///
/// The viewer normally deletes library entries. The wallpaper viewer needs two
/// extra things without teaching the viewer about the wallpaper feature: it can
/// delete the read-only private copy, and deleting the original has to be
/// confirmed and may drive the queue.
///
/// The task provides this policy above the viewer route; a normal gallery viewer
/// has none and keeps its behaviour untouched.
abstract interface class ViewerDeletePolicy {
  /// Whether [entry] is a private copy this policy owns and may delete.
  bool isPrivateCopy(AvesEntry entry);

  /// Whether [confirmDelete] replaces the viewer's own delete confirmation.
  ///
  /// A policy that already asked (and remembers "don't ask again") must not be
  /// followed by the standard bin/permanent prompt, or the opt-out would look
  /// broken.
  bool get replacesStandardConfirmation;

  /// Asks before deleting [entry]; false cancels.
  Future<bool> confirmDelete(BuildContext context, AvesEntry entry);

  /// Deletes a private copy; true means the policy handled the action and the
  /// viewer must not run its standard delete.
  Future<bool> deletePrivateCopy(BuildContext context, AvesEntry entry);

  /// A standard delete or move-to-bin completed successfully.
  void onDeleted(AvesEntry entry);
}

/// Provides a [ViewerDeletePolicy] to the viewer below it.
class ViewerDeletePolicyScope extends InheritedWidget {
  final ViewerDeletePolicy policy;

  const new({
    super.key,
    required this.policy,
    required super.child,
  });

  static ViewerDeletePolicy? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ViewerDeletePolicyScope>()?.policy;

  static ViewerDeletePolicy? read(BuildContext context) => context.getInheritedWidgetOfExactType<ViewerDeletePolicyScope>()?.policy;

  @override
  bool updateShouldNotify(ViewerDeletePolicyScope oldWidget) => policy != oldWidget.policy;
}
