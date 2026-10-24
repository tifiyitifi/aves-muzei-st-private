import 'dart:async';

import 'package:aves/features/muzei_wallpaper/model/wallpaper_display.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_about_dialog.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_auto_advance_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_effects_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_gestures_page.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_sources_page.dart';
import 'package:aves/features/muzei_wallpaper/view/slot_artwork_image.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Which wallpaper section a page is showing.
///
/// The sections are siblings, not a stack: switching between them replaces the
/// current page, exactly like Muzei's tabs did, while the artwork page keeps the
/// controller alive underneath.
enum WallpaperSection {
  artwork,
  sources,
  effects,
  gestures;

  String get routeName => switch (this) {
    WallpaperSection.artwork => '/muzei_wallpaper',
    WallpaperSection.sources => MuzeiWallpaperSourcesPage.routeName,
    WallpaperSection.effects => MuzeiWallpaperEffectsPage.routeName,
    WallpaperSection.gestures => MuzeiWallpaperGesturesPage.routeName,
  };
}

enum _WallpaperMenuAction {
  sources,
  effects,
  gestures,
  autoAdvance,
  titleMode,
  setWallpaper,
  about,
  refreshStatus,
  syncRuntime,
  debugInfo,
}

/// The wallpaper page's overflow menu.
///
/// Muzei puts sources and effects in a bottom tab bar. This port reaches the
/// page from the drawer instead, so the bar is gone and everything it held lives
/// here; the same button floats on every section page so switching never needs a
/// trip back to the artwork.
class WallpaperOverflowButton extends StatelessWidget {
  final WallpaperController controller;

  /// The section the button is drawn on; its menu entry is checked.
  final WallpaperSection section;

  final Color? color;

  /// Built lazily: the about dialog blurs the artwork behind it.
  final Widget Function()? aboutBackdrop;

  const new({
    super.key,
    required this.controller,
    required this.section,
    this.color,
    this.aboutBackdrop,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final active = controller.serviceActive;
    return PopupMenuButton<_WallpaperMenuAction>(
      icon: Icon(AIcons.more, color: color),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      onSelected: (action) => unawaited(_onSelected(context, action)),
      itemBuilder: (context) => [
        _sectionItem(l10n.muzeiWallpaperSources, _WallpaperMenuAction.sources, WallpaperSection.sources),
        _sectionItem(l10n.muzeiWallpaperEffects, _WallpaperMenuAction.effects, WallpaperSection.effects),
        _sectionItem(l10n.muzeiWallpaperGestures, _WallpaperMenuAction.gestures, WallpaperSection.gestures),
        _item(l10n.muzeiWallpaperAutoAdvance, _WallpaperMenuAction.autoAdvance),
        _item(l10n.muzeiWallpaperTitleMode, _WallpaperMenuAction.titleMode),
        const PopupMenuDivider(),
        _item(
          active ? l10n.muzeiWallpaperActive : l10n.muzeiWallpaperSetAction,
          _WallpaperMenuAction.setWallpaper,
          checked: active,
        ),
        _item(l10n.muzeiWallpaperAbout, _WallpaperMenuAction.about),
        if (kDebugMode) ...[
          const PopupMenuDivider(),
          _item(l10n.muzeiWallpaperRefreshStatus, _WallpaperMenuAction.refreshStatus),
          _item(l10n.muzeiWallpaperSyncRuntime, _WallpaperMenuAction.syncRuntime),
          _item(l10n.muzeiWallpaperDebugInfo, _WallpaperMenuAction.debugInfo),
        ],
      ],
    );
  }

  /// Every entry gets the same row, so labels line up whether or not they are
  /// checked and the mark always sits at the trailing edge.
  PopupMenuItem<_WallpaperMenuAction> _item(
    String label,
    _WallpaperMenuAction action, {
    bool checked = false,
    IconData? marker,
  }) {
    return PopupMenuItem(
      value: action,
      child: _CheckedRow(checked: checked, icon: marker, child: Text(label)),
    );
  }

  PopupMenuItem<_WallpaperMenuAction> _sectionItem(
    String label,
    _WallpaperMenuAction action,
    WallpaperSection target,
  ) {
    // A radio mark, not a checkmark: this is "where you are", not "done".
    return _item(label, action, checked: section == target, marker: AIcons.current);
  }

  Future<void> _onSelected(BuildContext context, _WallpaperMenuAction action) async {
    switch (action) {
      case _WallpaperMenuAction.sources:
        await _openSection(context, WallpaperSection.sources);
      case _WallpaperMenuAction.effects:
        await _openSection(context, WallpaperSection.effects);
      case _WallpaperMenuAction.gestures:
        await _openSection(context, WallpaperSection.gestures);
      case _WallpaperMenuAction.autoAdvance:
        await _openAutoAdvance(context);
      case _WallpaperMenuAction.titleMode:
        await _showTitleMode(context);
      case _WallpaperMenuAction.setWallpaper:
        await _setWallpaper(context);
      case _WallpaperMenuAction.about:
        await _showAbout(context);
      case _WallpaperMenuAction.refreshStatus:
        await controller.refreshServiceActive();
      case _WallpaperMenuAction.syncRuntime:
        await controller.syncRuntime();
      case _WallpaperMenuAction.debugInfo:
        await _showDebugInfo(context);
    }
  }

  /// Siblings replace each other, so repeatedly switching never grows the stack.
  ///
  /// Selecting the current section re-creates it, which is the cheapest refresh
  /// and keeps one meaning for every entry.
  Future<void> _openSection(BuildContext context, WallpaperSection target) async {
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    final page = switch (target) {
      WallpaperSection.sources => MuzeiWallpaperSourcesPage(controller: controller),
      WallpaperSection.effects => MuzeiWallpaperEffectsPage(controller: controller),
      WallpaperSection.gestures => MuzeiWallpaperGesturesPage(controller: controller),
      WallpaperSection.artwork => null,
    };
    if (page == null) {
      // Only the artwork page owns the controller; close the sections instead of
      // replacing it, which would dispose the controller under the new page.
      navigator.popUntil((route) => route.settings.name == WallpaperSection.artwork.routeName);
      return;
    }
    final route = MaterialPageRoute<void>(
      settings: RouteSettings(name: target.routeName),
      builder: (_) => page,
    );
    if (section == WallpaperSection.artwork) {
      await navigator.push(route);
    } else {
      await navigator.pushReplacement(route);
    }
  }

  Future<void> _setWallpaper(BuildContext context) async {
    final opened = await controller.openChooser();
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.muzeiWallpaperChooserUnavailable)),
    );
  }

  Future<void> _showAbout(BuildContext context) {
    return showMuzeiWallpaperAbout(
      context,
      artwork: aboutBackdrop?.call() ?? const ColoredBox(color: Colors.black),
    );
  }

  /// Auto-advance is scheduled by the native worker, so it keeps running when
  /// the page is closed; this page only edits the contract.
  Future<void> _openAutoAdvance(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: MuzeiWallpaperAutoAdvancePage.routeName),
        builder: (_) => MuzeiWallpaperAutoAdvancePage(controller: controller),
      ),
    );
  }

  Future<void> _showTitleMode(BuildContext context) {
    final selected = controller.prefs.titleMode;
    final l10n = context.l10n;
    final labels = {
      WallpaperTitleMode.fileName: l10n.muzeiWallpaperTitleFileName,
      WallpaperTitleMode.sourceName: l10n.muzeiWallpaperTitleSourceName,
    };
    return showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.muzeiWallpaperTitleMode),
        children: [
          for (final mode in WallpaperTitleMode.values)
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(controller.prefs.setTitleMode(mode));
              },
              child: _CheckedRow(
                checked: mode == selected,
                child: Text(labels[mode]!),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showDebugInfo(BuildContext context) {
    final state = controller.state;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.muzeiWallpaperDebugInfo),
        content: SelectableText(
          'generation ${state.generation}\n'
          'current slot ${state.current} · entry ${controller.current?.artwork.entryId ?? '-'}\n'
          'next slot ${state.next} · entry ${controller.next?.artwork.entryId ?? '-'}\n'
          'next2 slot ${state.next2} · entry ${controller.next2?.artwork.entryId ?? '-'}\n'
          'recent ${state.recent.map((artwork) => artwork.entryId).join(', ')}\n'
          'source ${controller.resolution?.status.name ?? '-'} · total ${controller.resolution?.total ?? 0}\n'
          'service ${controller.serviceActive ? 'active' : 'inactive'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }
}

class _CheckedRow extends StatelessWidget {
  final bool checked;

  /// The trailing mark: a checkmark by default, or a radio mark for "you are
  /// here".
  final IconData? icon;

  final Widget child;

  const new({required this.checked, this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: child),
        if (checked)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(icon ?? AIcons.checked, size: 20),
          ),
      ],
    );
  }
}

/// The same overflow menu as a floating round button.
///
/// Muzei kept its tabs on every screen; the sections here are separate pages, so
/// the menu floats on them too and switching never needs a trip back to the
/// artwork.
class WallpaperOverflowFab extends StatelessWidget {
  final WallpaperController controller;
  final WallpaperSection section;

  const new({
    super.key,
    required this.controller,
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: colors.secondaryContainer,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: WallpaperOverflowButton(
          controller: controller,
          section: section,
          color: colors.onSecondaryContainer,
          aboutBackdrop: () => wallpaperAboutBackdrop(controller),
        ),
      ),
    );
  }
}

/// Backdrop for the about dialog when the caller is not the artwork page.
///
/// Only the baked slot is available there: the in-memory fallback preview is
/// owned by the page. A black backdrop is a fine answer when nothing is baked.
Widget wallpaperAboutBackdrop(WallpaperController controller) {
  final slot = controller.current;
  final file = controller.currentFile;
  if (slot == null || file == null) return const ColoredBox(color: Colors.black);
  return Image(
    image: SlotArtworkImage(file: file, contentKey: slot.artwork.entryId),
    fit: BoxFit.cover,
  );
}
