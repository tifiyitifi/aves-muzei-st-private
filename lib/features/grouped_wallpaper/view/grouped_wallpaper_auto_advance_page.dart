import 'dart:async';

import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/view/wallpaper_interval_label.dart';
import 'package:aves/features/wallpaper_auto_advance/view/widgets/wallpaper_interval_more_button.dart';
import 'package:aves/features/wallpaper_auto_advance/view/widgets/wallpaper_interval_option_list.dart';
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
  final WallpaperGroupController controller;

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
            actions: const [WallpaperIntervalMoreButton()],
          ),
          body: group == null
              ? const SizedBox.shrink()
              : SafeArea(
                  child: ListView(
                    children: [
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
                      WallpaperIntervalOptionList(
                        selected: group.interval,
                        onSelected: (interval) => unawaited(_setInterval(interval)),
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
    await controller.setAutoAdvance(groupId, ordering: ordering);
    await wallpaperEngineLink.refreshSchedule();
  }

  Future<void> _setInterval(WallpaperAdvanceInterval interval) async {
    await controller.setAutoAdvance(groupId, interval: interval);
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
}

/// The one-line interval summary shown under the menu entry.
String groupedWallpaperAutoAdvanceSummary(BuildContext context, WallpaperGroup group) => wallpaperAdvanceIntervalLabel(context, group.interval);

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
