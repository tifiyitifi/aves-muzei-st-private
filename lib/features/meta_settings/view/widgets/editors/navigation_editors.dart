import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_selection_list_tile.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/text.dart';
import 'package:aves/view/view.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

/// Custom editor for the home page (its options depend on the current custom
/// collection / explorer path, so it cannot be a plain enum def).
class HomePageEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => MetaSelectionListTile<_HomeOption>(
        values: [
          const _HomeOption(HomePageSetting.collection),
          const _HomeOption(HomePageSetting.albums),
          const _HomeOption(HomePageSetting.tags),
          const _HomeOption(HomePageSetting.explorer),
          if (settings.homeCustomCollection.isNotEmpty) _HomeOption(HomePageSetting.collection, customCollection: settings.homeCustomCollection),
          if (settings.homeCustomExplorerPath != null) _HomeOption(HomePageSetting.explorer, customExplorerPath: settings.homeCustomExplorerPath),
        ],
        getName: (context, value) => value.getName(context),
        selector: (context, settings) => _HomeOption(
          settings.homePage,
          customCollection: settings.homeCustomCollection,
          customExplorerPath: settings.homeCustomExplorerPath,
        ),
        onSelection: (value) => settings.setHome(
          value.page,
          customCollection: value.customCollection,
          customExplorerPath: value.customExplorerPath,
        ),
        tileTitle: def.title,
        dialogTitle: context.l10n.settingsHomeDialogTitle,
        optionSubtitleBuilder: (value) => value.getDetails(context),
      );
}

@immutable
class _HomeOption {
  final HomePageSetting page;
  final Set<CollectionFilter> customCollection;
  final String? customExplorerPath;

  const new(
    this.page, {
    this.customCollection = const {},
    this.customExplorerPath,
  });

  String getName(BuildContext context) {
    final pageName = page.getName(context);
    switch (page) {
      case .collection:
        return customCollection.isNotEmpty ? context.l10n.setHomeCustom : pageName;
      case .explorer:
        return customExplorerPath != null ? context.l10n.setHomeCustom : pageName;
      default:
        return pageName;
    }
  }

  String? getDetails(BuildContext context) {
    switch (page) {
      case .collection:
        final filters = customCollection;
        return filters.isNotEmpty ? [context.l10n.collectionPageTitle, filters.map((v) => v.getLabel(context)).join(', ')].join(AText.separator) : null;
      case .explorer:
        final path = customExplorerPath;
        return path != null ? [context.l10n.explorerPageTitle, pContext.basename(path)].join(AText.separator) : null;
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _HomeOption && runtimeType == other.runtimeType && page == other.page && const DeepCollectionEquality().equals(customCollection, other.customCollection) && customExplorerPath == other.customExplorerPath);

  @override
  int get hashCode => page.hashCode ^ customCollection.hashCode ^ customExplorerPath.hashCode;
}
