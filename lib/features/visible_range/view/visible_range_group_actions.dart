/// The group an "edit group" overflow action targets.
///
/// The page offers the action in both plain states: with nothing selected it
/// edits the current group, and a single selected group tile edits itself.
/// A condition selection, or several selected groups, has no single target and
/// resolves to null so the entry is left out. Group 0 (「Unrestricted」) still
/// resolves here: the caller is what refuses it, because it holds no conditions.
String? visibleRangeEditGroupId({
  required bool selecting,
  required int selectedItemCount,
  required Iterable<String> selectedGroupIds,
  required String currentGroupId,
}) {
  if (!selecting || selectedItemCount == 0) return currentGroupId;
  final ids = selectedGroupIds.toList();
  if (selectedItemCount == 1 && ids.length == 1) return ids.single;
  return null;
}
