import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_multi_selection_list_tile.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/ref/bursts.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Custom editor for the burst detection patterns.
class BurstPatternsEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => MetaMultiSelectionListTile<String>(
        values: BurstPatterns.options,
        getName: (context, value) => BurstPatterns.getName(value),
        selector: (context, settings) => settings.collectionBurstPatterns,
        onSelection: (value) => settings.collectionBurstPatterns = value,
        tileTitle: def.title,
        noneSubtitle: context.l10n.settingsCollectionBurstPatternsNone,
        optionSubtitleBuilder: (value) => '${Unicode.FSI}${BurstPatterns.getExample(value)}${Unicode.PDI}',
      );
}
