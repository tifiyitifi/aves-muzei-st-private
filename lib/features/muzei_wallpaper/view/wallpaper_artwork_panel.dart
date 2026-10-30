import 'package:material_ui/material_ui.dart';

/// The bottom chrome of an artwork screen, shared by the Muzei page and the
/// grouped wallpaper view.
///
/// Muzei's artwork screen puts everything the user needs in one row floating
/// over the photo: the artwork's name, the line that says what touching it does,
/// and the trailing actions. The grouped wallpaper shows the same thing with
/// different words (its group and count stand in for Muzei's "touch to view"),
/// so the layout and the gestures live here once instead of drifting apart in
/// two pages that are meant to look the same.
///
/// [subtitle] is the interactive line: a tap opens the photo in the viewer, a
/// long press hands it to another app. [status] is a non-interactive note above
/// it (Muzei uses it for "source empty" and similar).
class WallpaperArtworkPanel extends StatelessWidget {
  final String? title;

  /// A non-interactive note between the title and [subtitle].
  final String? status;

  /// The line that carries the view/open-with gestures.
  final String? subtitle;

  final VoidCallback onViewArtwork;
  final VoidCallback onOpenWith;

  /// Buttons after the text block, e.g. next and the overflow menu.
  final List<Widget> actions;

  const new({
    super.key,
    this.title,
    this.status,
    this.subtitle,
    required this.onViewArtwork,
    required this.onOpenWith,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = title;
    final statusText = status;
    final subtitleText = subtitle;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: .88)],
        ),
      ),
      child: SafeArea(
        top: false,
        // The grouped view is immersive, so `padding` drops to zero once the
        // bars are hidden while the navigation/gesture bar still covers the
        // bottom edge; the raw view inset keeps the actions reachable there.
        minimum: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 48, 4, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (titleText != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        // The title carries the same actions as the subtitle:
                        // it is the line users point at when they want to see
                        // the artwork, so both must behave alike.
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onViewArtwork,
                          onLongPress: onOpenWith,
                          child: Text(
                            titleText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ),
                    if (statusText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 16),
                        child: Text(
                          statusText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ),
                    // Long press only fires on this line: the rest of the screen
                    // toggles the chrome instead.
                    if (subtitleText != null)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onViewArtwork,
                        onLongPress: onOpenWith,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(2, 10, 24, 10),
                          child: Text(
                            subtitleText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                              shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
