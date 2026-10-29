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
  SettingsCategory.language: (
    title: (context) => context.l10n.settingsLanguageSectionTitle,
    icon: (context) => MetaTileLeading(
          icon: AIcons.language,
          color: context.select<AvesColorsData, Color>((v) => v.language),
        ),
  ),
  SettingsCategory.accessibility: (
    title: (context) => context.l10n.settingsAccessibilitySectionTitle,
    icon: (context) => MetaTileLeading(
          icon: AIcons.accessibility,
          color: context.select<AvesColorsData, Color>((v) => v.accessibility),
        ),
  ),
  SettingsCategory.privacy: (
    title: (context) => context.l10n.settingsPrivacySectionTitle,
    icon: (context) => MetaTileLeading(
          icon: AIcons.privacy,
          color: context.select<AvesColorsData, Color>((v) => v.privacy),
        ),
  ),
  SettingsCategory.viewer: (
    title: (context) => context.l10n.settingsViewerSectionTitle,
    icon: (context) => MetaTileLeading(
          icon: AIcons.image,
          color: context.select<AvesColorsData, Color>((v) => v.image),
        ),
  ),
  SettingsCategory.video: (
    title: (context) => context.l10n.settingsVideoSectionTitle,
    icon: (context) => MetaTileLeading(
          icon: AIcons.video,
          color: context.select<AvesColorsData, Color>((v) => v.video),
        ),
  ),
  SettingsCategory.thumbnails: (
    title: (context) => context.l10n.settingsThumbnailSectionTitle,
    icon: (context) => MetaTileLeading(
          icon: AIcons.thumbnails,
          color: context.select<AvesColorsData, Color>((v) => v.thumbnails),
        ),
  ),
  SettingsCategory.navigation: (
    title: (context) => context.l10n.settingsNavigationSectionTitle,
    icon: (context) => MetaTileLeading(
          icon: AIcons.home,
          color: context.select<AvesColorsData, Color>((v) => v.navigation),
        ),
  ),
  SettingsCategory.wallpaper: (
    title: (context) => context.l10n.settingsWallpaperSectionTitle,
    icon: (context) => MetaTileLeading(
          icon: AIcons.wallpaper,
          color: context.select<AvesColorsData, Color>((v) => v.fromHue(260)),
        ),
  ),
};
