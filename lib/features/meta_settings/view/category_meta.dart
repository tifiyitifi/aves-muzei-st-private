import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_tile_leading.dart';
import 'package:aves/theme/colors.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Title and leading badge of a v2 category.
typedef MetaCategoryMeta = ({String Function(BuildContext context) title, Widget Function(BuildContext context) icon});

/// Categories rendered from the catalog. A category absent here is served by
/// the fork-owned legacy fallback instead.
final Map<SettingsCategory, MetaCategoryMeta> metaCategoryMeta = {
  SettingsCategory.display: (
    title: (context) => context.l10n.settingsDisplaySectionTitle,
    icon: (context) => MetaTileLeading(
          icon: AIcons.display,
          color: context.select<AvesColorsData, Color>((v) => v.display),
        ),
  ),
  SettingsCategory.advanced: (
    title: (context) => context.l10n.settingsAdvancedSectionTitle,
    icon: (context) => MetaTileLeading(
          icon: AIcons.settings,
          color: context.select<AvesColorsData, Color>((v) => v.fromHue(200)),
        ),
  ),
};
