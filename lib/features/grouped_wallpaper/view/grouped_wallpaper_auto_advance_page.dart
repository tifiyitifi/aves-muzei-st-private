import 'dart:async';

import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_range_controller.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

/// Edits one wallpaper group's auto-advance interval and ordering.
///
/// The contract belongs to the group, so a private group can stay still while a
/// public one rotates. The choices are Muzei's, and the scheduling itself lives in
/// the shared native WorkManager chain; this page only writes the group and asks
/// the engine to re-apply the interval when the edited group is the one playing.
///
/// Like effects, the values are written immediately rather than through the page's
/// range draft: they are preferences, not range edits.
class GroupedWallpaperAutoAdvancePage extends StatelessWidget {
  static const routeName = '/wallpaper_groups/auto_advance';

  final String groupId;
  final WallpaperGroupRangeController controller;

  const new({
    super.key,
    required this.groupId,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final group = controller.groups.firstWhereOrNull((candidate) => candidate.id == groupId);
        return AvesScaffold(
          appBar: AppBar(
            title: Text(l10n.muzeiWallpaperAutoAdvance),
          ),
          body: group == null
              ? const SizedBox.shrink()
              : SafeArea(
                  child: ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          l10n.wallpaperGroupAutoAdvanceHint,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      _SectionHeader(l10n.muzeiWallpaperAutoAdvanceOrdering),
                      RadioGroup<GroupedWallpaperOrdering>(
                        groupValue: group.ordering,
                        onChanged: (ordering) {
                          if (ordering != null) unawaited(_setOrdering(ordering));
                        },
                        child: Column(
                          children: [
                            for (final ordering in GroupedWallpaperOrdering.values)
                              RadioListTile<GroupedWallpaperOrdering>(
                                value: ordering,
                                title: Text(_orderingLabel(context, ordering)),
                                subtitle: Text(_orderingHint(context, ordering)),
                              ),
                          ],
                        ),
                      ),
                      const Divider(),
                      _SectionHeader(l10n.muzeiWallpaperAutoAdvanceInterval),
                      RadioGroup<WallpaperInterval>(
                        groupValue: group.interval,
                        onChanged: (interval) {
                          if (interval != null) unawaited(_setInterval(interval));
                        },
                        child: Column(
                          children: [
                            for (final interval in WallpaperInterval.values)
                              RadioListTile<WallpaperInterval>(
                                value: interval,
                                title: Text(_intervalLabel(context, interval)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  /// Writes the ordering, then re-applies the schedule: the interval is what the
  /// scheduler stores, but the engine re-reads the whole contract.
  Future<void> _setOrdering(GroupedWallpaperOrdering ordering) async {
    await controller.groupController.setAutoAdvance(groupId, ordering: ordering);
    await wallpaperEngineLink.refreshSchedule();
  }

  Future<void> _setInterval(WallpaperInterval interval) async {
    await controller.groupController.setAutoAdvance(groupId, interval: interval);
    await wallpaperEngineLink.refreshSchedule();
  }

  static String _orderingLabel(BuildContext context, GroupedWallpaperOrdering ordering) {
    final l10n = context.l10n;
    return switch (ordering) {
      GroupedWallpaperOrdering.inOrder => l10n.muzeiWallpaperAutoAdvanceOrderingInOrder,
      GroupedWallpaperOrdering.newThenRandom => l10n.muzeiWallpaperAutoAdvanceOrderingNewThenRandom,
      GroupedWallpaperOrdering.random => l10n.muzeiWallpaperAutoAdvanceOrderingRandom,
    };
  }

  static String _orderingHint(BuildContext context, GroupedWallpaperOrdering ordering) {
    final l10n = context.l10n;
    return switch (ordering) {
      GroupedWallpaperOrdering.inOrder => l10n.muzeiWallpaperAutoAdvanceOrderingInOrderHint,
      GroupedWallpaperOrdering.newThenRandom => l10n.muzeiWallpaperAutoAdvanceOrderingNewThenRandomHint,
      GroupedWallpaperOrdering.random => l10n.muzeiWallpaperAutoAdvanceOrderingRandomHint,
    };
  }

  static String _intervalLabel(BuildContext context, WallpaperInterval interval) {
    final l10n = context.l10n;
    return switch (interval) {
      WallpaperInterval.m15 => l10n.muzeiWallpaperAutoAdvanceMinutes(15),
      WallpaperInterval.m30 => l10n.muzeiWallpaperAutoAdvanceMinutes(30),
      WallpaperInterval.h1 => l10n.muzeiWallpaperAutoAdvanceHours(1),
      WallpaperInterval.h3 => l10n.muzeiWallpaperAutoAdvanceHours(3),
      WallpaperInterval.h6 => l10n.muzeiWallpaperAutoAdvanceHours(6),
      WallpaperInterval.h24 => l10n.muzeiWallpaperAutoAdvanceDays(1),
      WallpaperInterval.h72 => l10n.muzeiWallpaperAutoAdvanceDays(3),
      WallpaperInterval.never => l10n.muzeiWallpaperAutoAdvanceOff,
    };
  }
}

/// The one-line interval summary shown under the menu entry.
String groupedWallpaperAutoAdvanceSummary(BuildContext context, WallpaperGroup group) =>
    GroupedWallpaperAutoAdvancePage._intervalLabel(context, group.interval);

class _SectionHeader extends StatelessWidget {
  final String title;

  const new(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
