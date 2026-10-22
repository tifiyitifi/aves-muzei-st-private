import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/bars/floating_bar.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/extensions/media_query.dart';
import 'package:aves/widgets/navigation/nav_bar/nav_bar.dart';
import 'package:material_ui/material_ui.dart';

/// What the browse-only surface can show.
///
/// Exactly two things: the timeline and the album list. Both read the media
/// store directly, so neither waits for the catalogued library.
enum BrowseView { timeline, albums }

/// The bottom bar while the browser is the library surface.
///
/// The entries are fixed, the way a gallery's own navigation is: photos and
/// albums work, videos and favourites are greyed and inert because they answer
/// from catalogued data the import is still building. Keeping the two of them
/// visible (rather than dropping them) keeps the shape of the bar the user gets
/// back once the import finishes — but a greyed entry takes no tap at all, so
/// nothing promises an action that cannot happen.
class BrowseOnlyBottomBar extends StatelessWidget {
  final BrowseView view;
  final ValueChanged<BrowseView> onSelect;

  const new({
    super.key,
    required this.view,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = <_BarEntry>[
      _BarEntry(view: BrowseView.timeline, icon: AIcons.image, label: l10n.browseOnlyTimelineTab),
      _BarEntry(view: BrowseView.albums, icon: AIcons.album, label: l10n.browseOnlyAlbumsTab),
      // The two that need the catalogued library. They are not a template for
      // the collection's own bar: they mirror what the full app offers, so the
      // handoff does not rearrange the navigation under the user's finger.
      _BarEntry(view: null, icon: AIcons.video, label: l10n.browseOnlyVideosTab),
      _BarEntry(view: null, icon: AIcons.favourite, label: l10n.drawerCollectionFavourites),
    ];
    final safeBottomPadding = MediaQuery.of(context).safeBottomPadding;
    return SafeArea(
      bottom: false,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: Padding(
          padding: AppBottomNavBar.getMargin(safeBottomPadding),
          child: AvesFloatingBar(
            margin: EdgeInsets.zero,
            builder: (context, backgroundColor, child) => Material(
              color: backgroundColor,
              child: SizedBox(
                height: kBottomNavigationBarHeight,
                child: Row(
                  children: [
                    for (final entry in entries) Expanded(child: _buildEntry(context, entry)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntry(BuildContext context, _BarEntry entry) {
    final theme = Theme.of(context);
    final target = entry.view;
    final selected = target != null && target == view;
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(entry.icon, size: 24, color: color),
        const SizedBox(height: 2),
        Text(
          entry.label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
    if (target == null) {
      // Dimmed and inert: no ink response, no tap handler, so the entry cannot
      // even flash a ripple that implies something will happen.
      return Semantics(
        label: entry.label,
        enabled: false,
        child: Opacity(opacity: .35, child: content),
      );
    }
    return InkResponse(
      onTap: () {
        if (!selected) onSelect(target);
      },
      child: content,
    );
  }
}

class _BarEntry {
  /// The view a tap opens, or null when the entry needs the catalogued library.
  final BrowseView? view;
  final IconData icon;
  final String label;

  const new({
    required this.view,
    required this.icon,
    required this.label,
  });
}
