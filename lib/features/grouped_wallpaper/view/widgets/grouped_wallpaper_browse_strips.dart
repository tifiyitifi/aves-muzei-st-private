import 'dart:async';

import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_restore_notice.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_restore_bar.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/features/wallpaper_lock/view/wallpaper_lock_prompt.dart';
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

/// The strips a grouped-wallpaper browsing surface can put above its content.
///
/// Ordered as they stack: the wallpaper notice outranks the browsing ones, and
/// the "range ignored" reminder outranks the empty-set explanation it replaces.
enum GroupedWallpaperBrowseStrip {
  /// The live wallpaper stopped and can be re-applied.
  restore,

  /// The gallery range is temporarily ignored, with the way back.
  suspended,

  /// The gallery range hides every photo of the group.
  emptyScope,
}

/// Which strips to show, in order.
///
/// A suspended range is worth saying even when the media set is not empty: the
/// user asked for it explicitly, and without a reminder the only way back is a
/// menu they may not find. It replaces the empty-set explanation, which cannot
/// apply while the range is ignored.
List<GroupedWallpaperBrowseStrip> groupedWallpaperBrowseStrips({
  required bool restoreOffered,
  required bool gallerySuspended,
  required bool awaitingFirstWindow,
  required bool isEmpty,
  required VisibleRangeBrowsingOverlay? overlay,
  required bool galleryRestricted,
}) {
  final strips = <GroupedWallpaperBrowseStrip>[];
  if (restoreOffered) strips.add(GroupedWallpaperBrowseStrip.restore);
  if (gallerySuspended) {
    strips.add(GroupedWallpaperBrowseStrip.suspended);
  } else if (!awaitingFirstWindow &&
      groupedWallpaperScopeHidesMediaSet(
        isEmpty: isEmpty,
        overlay: overlay,
        galleryRestricted: galleryRestricted,
      )) {
    strips.add(GroupedWallpaperBrowseStrip.emptyScope);
  }
  return strips;
}

/// The strips the grouped wallpaper puts above a browsable surface.
///
/// They are all about the same thing — browsing and the wallpaper disagreeing —
/// so they share one shell: only the first visible strip takes over the status
/// bar inset the pages below draw themselves, or stacked strips would leave a
/// double gap.
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
        final overlay = VisibleRangeGate.overlay;
        // A lens still waiting for its first window reports "empty" for a
        // moment; explaining that would make the strip flash on every filter
        // change.
        final strips = groupedWallpaperBrowseStrips(
          restoreOffered: groupedWallpaperRestoreNotice.isOffered,
          gallerySuspended: overlay?.gallerySuspended ?? false,
          awaitingFirstWindow: lens.awaitingFirstWindow,
          isEmpty: lens.isEmpty,
          overlay: overlay,
          galleryRestricted: VisibleRangeGate.galleryRestricted,
        );
        if (strips.isEmpty) return child;
        return Column(
          children: [
            for (final (index, strip) in strips.indexed)
              switch (strip) {
                GroupedWallpaperBrowseStrip.restore => const GroupedWallpaperRestoreBar(),
                GroupedWallpaperBrowseStrip.suspended => _SuspendedRangeBar(takesStatusBarInset: index == 0),
                GroupedWallpaperBrowseStrip.emptyScope => _ScopeHintBar(
                    groupFilter: overlay!.groupFilter!,
                    locked: visibleRangeController.gallery.locked,
                    takesStatusBarInset: index == 0,
                  ),
              },
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
            ),
          ],
        );
      },
    );
  }
}

/// Reminds the user that the gallery range is ignored for this browsing session
/// and offers the one-tap way back.
class _SuspendedRangeBar extends StatelessWidget {
  /// Whether this strip owns the inset the page below would otherwise add.
  final bool takesStatusBarInset;

  const new({required this.takesStatusBarInset});

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
          top: takesStatusBarInset ? MediaQuery.paddingOf(context).top + 2 : 2,
          bottom: 2,
        ),
        child: Row(
          children: [
            Icon(AIcons.visibleRangeInactive, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.wallpaperGroupRangeIgnored,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => VisibleRangeGate.setGallerySuspended(false),
              style: TextButton.styleFrom(foregroundColor: colors.primary),
              child: Text(context.l10n.wallpaperGroupRangeRestore),
            ),
          ],
        ),
      ),
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
  /// A lock means "do not lift this range without proving the PIN", so the strip
  /// still offers the way out and asks for the PIN first.
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

  /// Asks for the visible-range PIN before ignoring a locked gallery range.
  Future<void> _ignore(BuildContext context) async {
    if (widget.locked && !await ensureVisibleRangeUnlocked(context)) return;
    if (!mounted) return;
    VisibleRangeGate.setGallerySuspended(true);
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
            TextButton(
              onPressed: () => unawaited(_ignore(context)),
              style: TextButton.styleFrom(foregroundColor: colors.primary),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.locked) ...[
                    const Icon(AIcons.locked, size: 16),
                    const SizedBox(width: 4),
                  ],
                  Text(context.l10n.groupedWallpaperScopeIgnore),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
