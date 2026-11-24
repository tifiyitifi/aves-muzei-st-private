import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/model/visible_range_write_back.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

/// The folded rule list and the promise outside the fold read the same
/// selection. A rule tap notifies this one value, so only these two subtrees
/// rebuild — the target grids, filter chips and text fields stay untouched.
class VisibleRangeWriteBackList extends StatelessWidget {
  final List<VisibleRangeWriteBackTarget> targets;
  final ValueListenable<Set<String>> selectedIds;
  final ValueChanged<String> onToggle;
  final bool loading;

  const new({
    super.key,
    required this.targets,
    required this.selectedIds,
    required this.onToggle,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: selectedIds,
      builder: (context, selected, _) {
        if (loading) return const SizedBox.shrink();
        if (targets.isEmpty) {
          return Text(l10n.visibleRangeWriteBackEmpty, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));
        }
        return Column(
          children: [
            for (final target in targets)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: selected.contains(target.usageId),
                enabled: !target.locked,
                title: Text(visibleRangeWriteBackTargetLabel(context, target)),
                subtitle: Text(visibleRangeWriteBackTargetLine(context, target)),
                onChanged: target.locked ? null : (_) => onToggle(target.usageId),
              ),
          ],
        );
      },
    );
  }
}

/// The write locations printed outside the fold. It listens to the same
/// selection as [VisibleRangeWriteBackList], so a tick updates it in place.
class VisibleRangeExpectedWrites extends StatelessWidget {
  final List<VisibleRangePinTarget> pinTargets;
  final Set<String> selectedPinIds;
  final List<VisibleRangeWriteBackTarget> writeBackTargets;
  final ValueListenable<Set<String>> selectedUsageIds;
  final VisibleRangeRuleKind? forcedRole;

  const new({
    super.key,
    required this.pinTargets,
    required this.selectedPinIds,
    required this.writeBackTargets,
    required this.selectedUsageIds,
    this.forcedRole,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: selectedUsageIds,
      builder: (context, selectedUsages, _) => Text(
        key: const Key('visibleRangeExpectedWrites'),
        visibleRangeExpectedWrites(
          context,
          pinTargets: pinTargets,
          selectedPinIds: selectedPinIds,
          writeBackTargets: writeBackTargets,
          selectedUsageIds: selectedUsages,
          forcedRole: forcedRole,
        ),
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
