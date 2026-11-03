import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The manual behind the effects sliders.
///
/// The page explains the model a slider cannot show: effects are stored per
/// surface, a change re-bakes the photo already on the wallpaper, and a wide
/// home frame deliberately ignores image fit and rotation because the launcher
/// pans it. Those are the questions the panel raises, so they get one page
/// instead of a tooltip per control.
class GroupedWallpaperEffectsHelpPage extends StatelessWidget {
  static const routeName = '/wallpaper_groups/effects/help';

  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = <({String title, String body})>[
      (title: l10n.groupedWallpaperEffectsAboutScopeTitle, body: l10n.groupedWallpaperEffectsAboutScopeBody),
      (title: l10n.groupedWallpaperEffectsAboutApplyTitle, body: l10n.groupedWallpaperEffectsAboutApplyBody),
      (title: l10n.groupedWallpaperEffectsAboutPreviewTitle, body: l10n.groupedWallpaperEffectsAboutPreviewBody),
      (title: l10n.groupedWallpaperEffectsAboutScrollTitle, body: l10n.groupedWallpaperEffectsAboutScrollBody),
      (title: l10n.groupedWallpaperEffectsAboutRotationTitle, body: l10n.groupedWallpaperEffectsAboutRotationBody),
      (title: l10n.groupedWallpaperEffectsAboutFitTitle, body: l10n.groupedWallpaperEffectsAboutFitBody),
    ];
    return AvesScaffold(
      appBar: AppBar(title: Text(l10n.groupedWallpaperEffectsAbout)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            for (final section in sections) _Section(title: section.title, body: section.body),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const new({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
