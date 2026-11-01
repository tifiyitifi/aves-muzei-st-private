import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Explains the auto-advance page reachable from both interval pickers.
///
/// The two pages share the same option list, so this page is shared too: it
/// covers scheduling, ordering, the option list, the editor limits and the three
/// list actions in one place instead of scattering hints under the picker.
class WallpaperIntervalAboutPage extends StatelessWidget {
  static const routeName = '/wallpaper_auto_advance/about';

  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesScaffold(
      appBar: AppBar(title: Text(l10n.wallpaperIntervalAbout)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            _AboutSection(body: l10n.wallpaperIntervalAboutWhat),
            _AboutSection(body: l10n.wallpaperIntervalAboutOrdering),
            _AboutSection(body: l10n.wallpaperIntervalAboutShared),
            _AboutSection(body: l10n.wallpaperIntervalAboutAdd),
            _AboutSection(body: l10n.wallpaperIntervalAboutDelete),
            _AboutSection(body: l10n.wallpaperIntervalAboutBuiltIn),
            _AboutSection(body: l10n.wallpaperIntervalAboutListActions),
            _AboutSection(body: l10n.wallpaperIntervalAboutBattery),
            _AboutSection(body: l10n.wallpaperIntervalAboutMuzei),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  final String body;

  const new({required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(body, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
