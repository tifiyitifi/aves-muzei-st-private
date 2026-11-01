import 'dart:async';

import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/wallpaper_auto_advance/view/widgets/wallpaper_interval_more_button.dart';
import 'package:aves/features/wallpaper_auto_advance/view/widgets/wallpaper_interval_option_list.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Auto-advance settings: how often the wallpaper moves and how the next
/// artwork is chosen.
///
/// Mirrors Muzei's Auto Advance screen (ordering + interval). The Wi-Fi-only
/// option is deliberately absent: our source is the local library, so there is
/// no download to wait for, and the setting would be meaningless.
///
/// The scheduling itself lives in the native WorkManager chain; this page only
/// edits the contract through [WallpaperController.setAutoAdvance].
class MuzeiWallpaperAutoAdvancePage extends StatelessWidget {
  static const routeName = '/muzei_wallpaper/auto_advance';

  final WallpaperController controller;

  const new({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: controller.prefs,
      builder: (context, _) {
        final value = controller.prefs.autoAdvance;
        return AvesScaffold(
          appBar: AppBar(
            title: Text(l10n.muzeiWallpaperAutoAdvance),
            actions: const [WallpaperIntervalMoreButton()],
          ),
          body: SafeArea(
            child: ListView(
              children: [
                _SectionHeader(l10n.muzeiWallpaperAutoAdvanceOrdering),
                RadioGroup<WallpaperOrdering>(
                  groupValue: value.ordering,
                  onChanged: (ordering) => unawaited(
                    controller.setAutoAdvance(value.copyWith(ordering: ordering)),
                  ),
                  child: Column(
                    children: [
                      for (final ordering in WallpaperOrdering.values)
                        RadioListTile<WallpaperOrdering>(
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
                  selected: value.interval,
                  onSelected: (interval) => unawaited(
                    controller.setAutoAdvance(value.copyWith(interval: interval)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _orderingLabel(BuildContext context, WallpaperOrdering ordering) {
    final l10n = context.l10n;
    return switch (ordering) {
      WallpaperOrdering.inOrder => l10n.muzeiWallpaperAutoAdvanceOrderingInOrder,
      WallpaperOrdering.newThenRandom => l10n.muzeiWallpaperAutoAdvanceOrderingNewThenRandom,
      WallpaperOrdering.random => l10n.muzeiWallpaperAutoAdvanceOrderingRandom,
    };
  }

  static String _orderingHint(BuildContext context, WallpaperOrdering ordering) {
    final l10n = context.l10n;
    return switch (ordering) {
      WallpaperOrdering.inOrder => l10n.muzeiWallpaperAutoAdvanceOrderingInOrderHint,
      WallpaperOrdering.newThenRandom => l10n.muzeiWallpaperAutoAdvanceOrderingNewThenRandomHint,
      WallpaperOrdering.random => l10n.muzeiWallpaperAutoAdvanceOrderingRandomHint,
    };
  }
}

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
