import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/view/collection_background_work_page.dart';
import 'package:aves/features/collection_paging/view/collection_paging_labels.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_sub_page_tile.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_list_subtitle.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/common.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/single_selection.dart';
import 'package:material_ui/material_ui.dart';

/// Custom editor for the collection engine (legacy full-load vs paged).
///
/// Reads and writes [collectionPagingPrefs] directly, bypassing the settings
/// engine and its guard: these keys are engine-independent by design.
class CollectionEngineEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: collectionPagingPrefs,
      builder: (context, child) {
        final engine = collectionPagingPrefs.engine;
        return ListTile(
          title: Text(def.title(context)),
          subtitle: AvesListSubtitle(collectionEngineName(context, engine)),
          onTap: () => showSelectionDialog<CollectionEngine>(
            context: context,
            builder: (context) => AvesSingleSelectionDialog<CollectionEngine>(
              initialValue: engine,
              options: {
                for (final v in CollectionEngine.values) v: collectionEngineName(context, v),
              },
              title: context.l10n.settingsCollectionEngineDialogTitle,
              optionSubtitleBuilder: (v) => v == engine ? null : collectionEngineDescription(context, v),
            ),
            onSelection: collectionPagingPrefs.setEngine,
          ),
        );
      },
    );
  }
}

/// Custom editor for the paged window size (memory budget per fetch).
class CollectionWindowSizeEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: collectionPagingPrefs,
      builder: (context, child) {
        final size = collectionPagingPrefs.windowSize;
        return ListTile(
          title: Text(def.title(context)),
          subtitle: AvesListSubtitle(context.l10n.collectionWindowSizeCount(size)),
          onTap: () => showSelectionDialog<int>(
            context: context,
            builder: (context) => AvesSingleSelectionDialog<int>(
              initialValue: size,
              options: {
                for (final v in CollectionPagingPrefs.windowSizePresets) v: context.l10n.collectionWindowSizeCount(v),
              },
              title: context.l10n.settingsCollectionWindowDialogTitle,
            ),
            onSelection: collectionPagingPrefs.setWindowSize,
          ),
        );
      },
    );
  }
}

/// Custom editor for the prefetch depth around the visible viewport.
class CollectionPrefetchScreensEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: collectionPagingPrefs,
      builder: (context, child) {
        final screens = collectionPagingPrefs.prefetchScreens;
        return ListTile(
          title: Text(def.title(context)),
          subtitle: AvesListSubtitle(context.l10n.collectionPrefetchScreens(screens)),
          onTap: () => showSelectionDialog<int>(
            context: context,
            builder: (context) => AvesSingleSelectionDialog<int>(
              initialValue: screens,
              options: {
                for (var v = 0; v <= CollectionPagingPrefs.maxPrefetchScreens; v++) v: context.l10n.collectionPrefetchScreens(v),
              },
              title: context.l10n.settingsCollectionPrefetchDialogTitle,
            ),
            onSelection: collectionPagingPrefs.setPrefetchScreens,
          ),
        );
      },
    );
  }
}

/// Custom editor for the large-collection threshold of the auto engine.
class CollectionThresholdEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: collectionPagingPrefs,
      builder: (context, child) {
        final threshold = collectionPagingPrefs.largeThreshold;
        return ListTile(
          title: Text(def.title(context)),
          subtitle: AvesListSubtitle(context.l10n.collectionThresholdCount(threshold)),
          onTap: () => showSelectionDialog<int>(
            context: context,
            builder: (context) => AvesSingleSelectionDialog<int>(
              initialValue: threshold,
              options: {
                for (final v in CollectionPagingPrefs.largeThresholdPresets) v: context.l10n.collectionThresholdCount(v),
              },
              title: context.l10n.settingsCollectionThresholdDialogTitle,
            ),
            onSelection: collectionPagingPrefs.setLargeThreshold,
          ),
        );
      },
    );
  }
}

/// Custom editor for the "ask before cataloguing" toggle.
///
/// Like its siblings, it reads and writes [collectionPagingPrefs] directly: the
/// key lives outside both settings stores, so the paged engine can read it
/// whatever store is authoritative.
class CollectionAskBeforeCatalogEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: collectionPagingPrefs,
      builder: (context, child) => SwitchListTile(
        title: Text(def.title(context)),
        value: collectionPagingPrefs.askBeforeCatalog,
        onChanged: collectionPagingPrefs.setAskBeforeCatalog,
      ),
    );
  }
}

/// Custom editor for the first-run background organization explainer.
///
/// A settings entry rather than a second copy of the text: the one-time dialog
/// says it once, and this keeps the same explanation — plus the live state —
/// reachable afterwards.
class CollectionBackgroundWorkEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => MetaSubPageTile(
        title: def.title,
        routeName: CollectionBackgroundWorkPage.routeName,
        builder: (context) => const CollectionBackgroundWorkPage(),
      );
}
