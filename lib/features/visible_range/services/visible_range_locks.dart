import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves_model/aves_model.dart';

/// Whether the locked visible range withholds an entry-set action.
///
/// The lock's permissions name library operations rather than app actions, so
/// each action maps to the closest permission: a copy relocates content like a
/// move, a clipboard copy leaves the device like a share, and every edit
/// (raster or metadata) needs the edit permission. Actions the lock does not
/// govern answer false, so an unlocked range changes nothing.
bool visibleRangeLocksEntrySetAction(EntrySetAction action) => switch (action) {
  .delete => !VisibleRangeGate.allows(VisibleRangeMutation.delete),
  .copy || .move => !VisibleRangeGate.allows(VisibleRangeMutation.move),
  .rename => !VisibleRangeGate.allows(VisibleRangeMutation.rename),
  .restore || .emptyBin => !VisibleRangeGate.allows(VisibleRangeMutation.trash),
  .share || .copyToClipboard => !VisibleRangeGate.allows(VisibleRangeMutation.share),
  .convert ||
  .rotateCCW ||
  .rotateCW ||
  .flip ||
  .editDate ||
  .editLocation ||
  .editTitleDescription ||
  .editRating ||
  .editTags ||
  .removeMetadata =>
    !VisibleRangeGate.allows(VisibleRangeMutation.edit),
  _ => false,
};

/// Whether the locked visible range withholds a single-entry viewer action.
bool visibleRangeLocksEntryAction(EntryAction action) => switch (action) {
  .delete => !VisibleRangeGate.allows(VisibleRangeMutation.delete),
  .copy || .move => !VisibleRangeGate.allows(VisibleRangeMutation.move),
  .rename => !VisibleRangeGate.allows(VisibleRangeMutation.rename),
  .restore => !VisibleRangeGate.allows(VisibleRangeMutation.trash),
  .share || .copyToClipboard => !VisibleRangeGate.allows(VisibleRangeMutation.share),
  .edit ||
  .rotateCCW ||
  .rotateCW ||
  .flip ||
  .convert ||
  .editDate ||
  .editLocation ||
  .editTitleDescription ||
  .editRating ||
  .editTags ||
  .removeMetadata =>
    !VisibleRangeGate.allows(VisibleRangeMutation.edit),
  _ => false,
};

/// Whether the locked visible range withholds an album-grid action.
bool visibleRangeLocksChipSetAction(ChipSetAction action) => switch (action) {
  .delete => !VisibleRangeGate.allows(VisibleRangeMutation.delete),
  .rename => !VisibleRangeGate.allows(VisibleRangeMutation.rename),
  .hide => !VisibleRangeGate.allows(VisibleRangeMutation.hide),
  .lockVault || .configureVault => !VisibleRangeGate.allows(VisibleRangeMutation.vault),
  _ => false,
};
