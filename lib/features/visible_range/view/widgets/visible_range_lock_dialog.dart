import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for the permissions of a locked range.
///
/// Both pages lock the same `VisibleRange`, so the dialog is shared: the caller
/// only chooses the preset it opens with and what to do with the answer.
class VisibleRangeLockDialog extends StatefulWidget {
  /// Preset the dialog opens with; the user can still change every permission.
  final VisibleRangeLockPreset initialPreset;

  const new({super.key, this.initialPreset = VisibleRangeLockPreset.readOnly});

  @override
  State<VisibleRangeLockDialog> createState() => _VisibleRangeLockDialogState();
}

class _VisibleRangeLockDialogState extends State<VisibleRangeLockDialog> {
  late VisibleRangeLockPreset _preset = widget.initialPreset;
  late VisibleRangePermissions _permissions = VisibleRangePermissions.of(_preset);

  void _applyPreset(VisibleRangeLockPreset? preset) {
    if (preset == null) return;
    setState(() {
      _preset = preset;
      _permissions = VisibleRangePermissions.of(preset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.visibleRangeLockSheetTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.visibleRangeLockSheetPreset),
            DropdownButton<VisibleRangeLockPreset>(
              value: _preset,
              isExpanded: true,
              onChanged: _applyPreset,
              items: [
                DropdownMenuItem(value: VisibleRangeLockPreset.readOnly, child: Text(l10n.visibleRangeLockSheetReadOnly)),
                DropdownMenuItem(value: VisibleRangeLockPreset.manageable, child: Text(l10n.visibleRangeLockSheetManageable)),
                DropdownMenuItem(value: VisibleRangeLockPreset.full, child: Text(l10n.visibleRangeLockSheetFull)),
              ],
            ),
            const Divider(),
            _permissionTile(l10n.visibleRangePermissionShare, (p) => p.share, (v) => _copy(share: v)),
            _permissionTile(l10n.visibleRangePermissionDelete, (p) => p.delete, (v) => _copy(delete: v)),
            _permissionTile(l10n.visibleRangePermissionEdit, (p) => p.edit, (v) => _copy(edit: v)),
            _permissionTile(l10n.visibleRangePermissionMove, (p) => p.move, (v) => _copy(move: v)),
            _permissionTile(l10n.visibleRangePermissionRename, (p) => p.rename, (v) => _copy(rename: v)),
            _permissionTile(l10n.visibleRangePermissionHide, (p) => p.hide, (v) => _copy(hide: v)),
            _permissionTile(l10n.visibleRangePermissionVault, (p) => p.vault, (v) => _copy(vault: v)),
            _permissionTile(l10n.visibleRangePermissionTrash, (p) => p.trash, (v) => _copy(trash: v)),
            _permissionTile(l10n.visibleRangePermissionMetadata, (p) => p.metadata, (v) => _copy(metadata: v)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
        TextButton(onPressed: () => Navigator.pop(context, _permissions), child: Text(l10n.visibleRangeLockConfirm)),
      ],
    );
  }

  Widget _permissionTile(String title, bool Function(VisibleRangePermissions p) read, VisibleRangePermissions Function(bool value) update) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: read(_permissions),
      onChanged: (value) => setState(() => _permissions = update(value)),
    );
  }

  VisibleRangePermissions _copy({
    bool? share,
    bool? delete,
    bool? edit,
    bool? move,
    bool? rename,
    bool? hide,
    bool? vault,
    bool? trash,
    bool? metadata,
  }) {
    return VisibleRangePermissions(
      share: share ?? _permissions.share,
      delete: delete ?? _permissions.delete,
      edit: edit ?? _permissions.edit,
      move: move ?? _permissions.move,
      rename: rename ?? _permissions.rename,
      hide: hide ?? _permissions.hide,
      vault: vault ?? _permissions.vault,
      trash: trash ?? _permissions.trash,
      metadata: metadata ?? _permissions.metadata,
    );
  }
}
