import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/view/collection_paging_labels.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
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
              optionSubtitleBuilder: (v) => v == engine ? null : context.l10n.collectionEngineDescription,
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
