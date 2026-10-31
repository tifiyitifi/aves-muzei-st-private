import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The shared explanation page reachable from both the visible-range page and
/// the wallpaper page.
///
/// Both pages can read both sections; the only difference is which one comes
/// first, so a reader lands on the side they opened the page from.
class VisibleRangeAboutPage extends StatelessWidget {
  static const routeName = '/visible_range/about';

  /// Whether the grouped-wallpaper section comes before the visible-range one.
  final bool wallpaperFirst;

  const new({super.key, this.wallpaperFirst = false});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesScaffold(
      appBar: AppBar(
        title: Text(wallpaperFirst ? l10n.aboutWallpaperTitle : l10n.aboutVisibleRangeTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Text(
              l10n.aboutVisibleRangeOrderNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (wallpaperFirst) ..._wallpaperSections(context) else ..._visibleRangeSections(context),
            if (wallpaperFirst) ..._visibleRangeSections(context) else ..._wallpaperSections(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _visibleRangeSections(BuildContext context) {
    final l10n = context.l10n;
    return [
      _AboutSection(title: l10n.aboutVisibleRangeTitle, body: l10n.aboutVisibleRangeWhat),
      _AboutSection(body: l10n.aboutVisibleRangeParts),
      _AboutSection(body: l10n.aboutVisibleRangeRestricted),
      _AboutSection(body: l10n.aboutVisibleRangeActivate),
      _AboutSection(body: l10n.aboutVisibleRangeLock),
      _AboutSection(body: l10n.aboutVisibleRangeLockPin),
      _AboutSection(body: l10n.aboutVisibleRangeWallpaper),
      _AboutSection(body: l10n.aboutVisibleRangeDefaults),
    ];
  }

  List<Widget> _wallpaperSections(BuildContext context) {
    final l10n = context.l10n;
    return [
      _AboutSection(title: l10n.aboutWallpaperTitle, body: l10n.aboutWallpaperWhat),
      _AboutSection(body: l10n.aboutWallpaperMuzei),
      _AboutSection(body: l10n.aboutWallpaperGroups),
      _AboutSection(body: l10n.aboutWallpaperAvailability),
      _AboutSection(body: l10n.aboutWallpaperSync),
      _AboutSection(body: l10n.aboutWallpaperScroll),
      _AboutSection(body: l10n.aboutWallpaperNotification),
      _AboutSection(body: l10n.aboutWallpaperLock),
      _AboutSection(body: l10n.aboutWallpaperOverwrite),
    ];
  }
}

class _AboutSection extends StatelessWidget {
  final String? title;
  final String body;

  const new({this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
          ],
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
