import 'dart:async';

import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
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
          ),
          body: SafeArea(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.muzeiWallpaperAutoAdvanceDescription,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
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
                RadioGroup<WallpaperInterval>(
                  groupValue: value.interval,
                  onChanged: (interval) => unawaited(
                    controller.setAutoAdvance(value.copyWith(interval: interval)),
                  ),
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
