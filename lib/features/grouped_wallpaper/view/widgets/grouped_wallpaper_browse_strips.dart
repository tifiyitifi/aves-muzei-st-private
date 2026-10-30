import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_restore_notice.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_restore_bar.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

/// Whether an empty media set is explained by the gallery range hiding the
/// group's photos.
///
/// The gallery range and a wallpaper group are independent data sets, and
/// browsing shows their intersection. When that intersection is empty while the
/// group itself has photos, the empty state alone reads as "this group has
/// nothing", which is exactly the confusion this strip answers. Group 0 has no
/// scope of its own, so it is never explained here.
bool groupedWallpaperScopeHidesMediaSet({
  required bool isEmpty,
  required VisibleRangeBrowsingOverlay? overlay,
  required bool galleryRestricted,
}) {
  if (!isEmpty || !galleryRestricted) return false;
  if (overlay == null || overlay.gallerySuspended) return false;
  return overlay.groupFilter != null;
}

/// The strips the grouped wallpaper puts above a browsable surface.
///
/// Both are about the same thing — browsing and the wallpaper disagreeing — so
/// they share one shell: only the first visible strip takes over the status bar
/// inset the pages below draw themselves, or two stacked strips would leave a
/// double gap. The notice comes first because a stopped wallpaper outranks a
/// scoped view.
class GroupedWallpaperBrowseStrips extends StatelessWidget {
  /// The collection on screen, read only for its emptiness.
  final PagedCollectionLens lens;

  final Widget child;

  const new({super.key, required this.lens, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([groupedWallpaperRestoreNotice, VisibleRangeGate.overlayListenable, visibleRangeController, lens]),
      builder: (context, _) {
        final restore = groupedWallpaperRestoreNotice.isOffered;
        final overlay = VisibleRangeGate.overlay;
        // A lens still waiting for its first window reports "empty" for a
        // moment; explaining that would make the strip flash on every filter
        // change.
        final scopeHint = !lens.awaitingFirstWindow &&
            groupedWallpaperScopeHidesMediaSet(
              isEmpty: lens.isEmpty,
              overlay: overlay,
              galleryRestricted: VisibleRangeGate.galleryRestricted,
            );
        if (!restore && !scopeHint) return child;
        return Column(
          children: [
            if (restore) const GroupedWallpaperRestoreBar(),
            if (scopeHint)
              _ScopeHintBar(
                groupFilter: overlay!.groupFilter!,
                locked: visibleRangeController.gallery.locked,
                takesStatusBarInset: !restore,
              ),
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
            ),
          ],
        );
      },
    );
  }
}

/// Says why the media set is empty and offers the one-tap way out.
///
/// The action only suspends the gallery range for this browsing session: the
/// saved range, and the wallpaper, are untouched.
class _ScopeHintBar extends StatefulWidget {
  final CollectionFilter groupFilter;

  /// Whether the gallery range is locked.
  ///
  /// A lock means "do not lift this range, not even temporarily", so the strip
  /// still explains the empty result but offers no way out.
  final bool locked;

  /// Whether this strip owns the inset the page below would otherwise add.
  final bool takesStatusBarInset;

  const new({required this.groupFilter, required this.locked, required this.takesStatusBarInset});

  @override
  State<_ScopeHintBar> createState() => _ScopeHintBarState();
}

class _ScopeHintBarState extends State<_ScopeHintBar> {
  late Future<int?> _count;

  @override
  void initState() {
    super.initState();
    _count = _countGroupImages();
  }

  @override
  void didUpdateWidget(_ScopeHintBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupFilter != widget.groupFilter) {
      _count = _countGroupImages();
    }
  }

  /// How many images the group alone holds, ignoring the gallery range.
  ///
  /// Only the wording depends on it: the strip itself is shown for the range
  /// intersection being empty, which is known without a query.
  Future<int?> _countGroupImages() async {
    final stats = await VisibleRangeCandidateStatsLoader.load([
      {MimeFilter.image, widget.groupFilter},
    ]);
    return stats.values.firstOrNull?.count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 16,
          end: 4,
          top: widget.takesStatusBarInset ? MediaQuery.paddingOf(context).top + 2 : 2,
          bottom: 2,
        ),
        child: Row(
          children: [
            Icon(AIcons.visibleRangeInactive, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: FutureBuilder<int?>(
                future: _count,
                builder: (context, snapshot) {
                  final count = snapshot.data;
                  return Text(
                    count == null ? context.l10n.groupedWallpaperScopeHidden : context.l10n.groupedWallpaperScopeHiddenCount(count),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            if (widget.locked)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
                child: Text(
                  context.l10n.visibleRangeWhenLocked,
                  style: theme.textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
                ),
              )
            else
              TextButton(
                onPressed: () => VisibleRangeGate.setGallerySuspended(true),
                style: TextButton.styleFrom(foregroundColor: colors.primary),
                child: Text(context.l10n.groupedWallpaperScopeIgnore),
              ),
          ],
        ),
      ),
    );
  }
}
