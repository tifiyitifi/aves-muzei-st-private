import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// What the user picked from a rule's action sheet.
enum VisibleRangeRuleAction {
  rename,
  moveToRestriction,
  moveToSupplement,
  moveToBase,
  activateReplace,
  activateAppend,
  delete,
}

/// Shows the actions available for one rule.
///
/// The gallery's visible-range page and the wallpaper-group page edit the same
/// `VisibleRangeRule`, so the sheet lives here instead of being duplicated: the
/// pages only differ in what they do with the answer.
///
/// Locked ranges keep the read-only actions (browse the rule in a media set);
/// every write is disabled, matching the controller's own guard.
Future<VisibleRangeRuleAction?> showVisibleRangeRuleActions(
  BuildContext context, {
  required VisibleRangeRule rule,
  required bool canEdit,
}) {
  final l10n = context.l10n;
  final title = visibleRangeRuleLabel(context, rule);
  return showModalBottomSheet<VisibleRangeRuleAction>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(title.isEmpty ? visibleRangeRuleKindLabel(context, rule.kind) : title),
            subtitle: Text(
              [rule.description, visibleRangeRuleKindLabel(context, rule.kind)].where((v) => v.isNotEmpty).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(AIcons.rename),
            title: Text(l10n.visibleRangeActionRename),
            enabled: canEdit,
            onTap: () => Navigator.pop(context, VisibleRangeRuleAction.rename),
          ),
          ListTile(
            leading: const Icon(AIcons.visibleRangeRestriction),
            title: Text(l10n.visibleRangeActionMoveToRestriction),
            enabled: canEdit && rule.kind != VisibleRangeRuleKind.restriction,
            onTap: () => Navigator.pop(context, VisibleRangeRuleAction.moveToRestriction),
          ),
          ListTile(
            leading: const Icon(AIcons.visibleRangeSupplement),
            title: Text(l10n.visibleRangeActionMoveToSupplement),
            enabled: canEdit && rule.kind != VisibleRangeRuleKind.supplement,
            onTap: () => Navigator.pop(context, VisibleRangeRuleAction.moveToSupplement),
          ),
          ListTile(
            leading: const Icon(AIcons.folder),
            title: Text(l10n.visibleRangeActionMoveToBase),
            enabled: canEdit,
            onTap: () => Navigator.pop(context, VisibleRangeRuleAction.moveToBase),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(AIcons.search),
            title: Text(l10n.visibleRangeActionActivateReplace),
            onTap: () => Navigator.pop(context, VisibleRangeRuleAction.activateReplace),
          ),
          ListTile(
            leading: const Icon(AIcons.add),
            title: Text(l10n.visibleRangeActionActivateAppend),
            onTap: () => Navigator.pop(context, VisibleRangeRuleAction.activateAppend),
          ),
          ListTile(
            leading: const Icon(AIcons.delete),
            title: Text(l10n.visibleRangeActionDelete),
            enabled: canEdit,
            onTap: () => Navigator.pop(context, VisibleRangeRuleAction.delete),
          ),
        ],
      ),
    ),
  );
}

/// Localized name of a rule section.
String visibleRangeRuleKindLabel(BuildContext context, VisibleRangeRuleKind kind) {
  final l10n = context.l10n;
  return switch (kind) {
    VisibleRangeRuleKind.restriction => l10n.visibleRangeRuleKindRestriction,
    VisibleRangeRuleKind.supplement => l10n.visibleRangeRuleKindSupplement,
  };
}
