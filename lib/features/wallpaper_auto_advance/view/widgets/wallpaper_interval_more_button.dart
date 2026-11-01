import 'dart:async';

import 'package:aves/features/wallpaper_auto_advance/services/wallpaper_interval_options_controller.dart';
import 'package:aves/features/wallpaper_auto_advance/view/wallpaper_interval_about_page.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The auto-advance page's overflow menu: the three list actions plus About.
///
/// Both the grouped-wallpaper page and the Muzei page mount it, because the
/// option list is shared. Explanations live in [WallpaperIntervalAboutPage],
/// not here: a menu is for acting, and the hints were only cluttering the picker.
enum _IntervalMenuAction {
  addDefaults,
  clearAll,
  resetToDefaults,
  about,
}

class WallpaperIntervalMoreButton extends StatelessWidget {
  /// Injectable for tests; defaults to the app-wide controller.
  final WallpaperIntervalOptionsController? controller;

  const new({super.key, this.controller});

  @override
  Widget build(BuildContext context) {
    final options = controller ?? wallpaperIntervalOptionsController;
    final l10n = context.l10n;
    // The catalog decides whether 「Add default intervals」 has anything to do.
    return ListenableBuilder(
      listenable: options,
      builder: (context, _) {
        final catalog = options.catalog;
        return PopupMenuButton<_IntervalMenuAction>(
          icon: const Icon(AIcons.more),
          tooltip: l10n.wallpaperIntervalMore,
          onSelected: (action) => unawaited(_onSelected(context, options, action)),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _IntervalMenuAction.addDefaults,
              enabled: catalog != null && catalog.missingDefaults.isNotEmpty,
              child: _menuRow(AIcons.restore, l10n.wallpaperIntervalAddDefaults),
            ),
            PopupMenuItem(
              value: _IntervalMenuAction.clearAll,
              child: _menuRow(AIcons.emptyBin, l10n.wallpaperIntervalClearAll),
            ),
            PopupMenuItem(
              value: _IntervalMenuAction.resetToDefaults,
              child: _menuRow(AIcons.reset, l10n.wallpaperIntervalResetDefaults),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _IntervalMenuAction.about,
              child: _menuRow(AIcons.info, l10n.wallpaperIntervalAbout),
            ),
          ],
        );
      },
    );
  }

  static Widget _menuRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(text)),
      ],
    );
  }

  Future<void> _onSelected(BuildContext context, WallpaperIntervalOptionsController controller, _IntervalMenuAction action) async {
    switch (action) {
      case _IntervalMenuAction.addDefaults:
        await controller.addMissingDefaults();
      case _IntervalMenuAction.clearAll:
        if (await _confirm(context, clearAll: true)) await controller.clearList();
      case _IntervalMenuAction.resetToDefaults:
        if (await _confirm(context, clearAll: false)) await controller.resetToDefaults();
      case _IntervalMenuAction.about:
        if (!context.mounted) return;
        await Navigator.maybeOf(context)?.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: WallpaperIntervalAboutPage.routeName),
            builder: (_) => const WallpaperIntervalAboutPage(),
          ),
        );
    }
  }

  /// Both destructive actions ask first: they change what every wallpaper can
  /// pick, and Reset also turns auto-advance off everywhere.
  static Future<bool> _confirm(BuildContext context, {required bool clearAll}) async {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(clearAll ? l10n.wallpaperIntervalClearAllTitle : l10n.wallpaperIntervalResetDefaultsTitle),
        content: Text(clearAll ? l10n.wallpaperIntervalClearAllMessage : l10n.wallpaperIntervalResetDefaultsMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: Text(clearAll ? l10n.wallpaperIntervalClearAll : l10n.wallpaperIntervalResetDefaults),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
