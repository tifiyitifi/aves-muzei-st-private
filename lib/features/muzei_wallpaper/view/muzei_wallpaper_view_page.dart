import 'dart:async';

import 'package:aves/features/muzei_wallpaper/model/wallpaper_cover.dart';
import 'package:aves/widgets/aves_app.dart';
import 'package:material_ui/material_ui.dart';

/// Immersive, artwork-only view of what the wallpaper page is showing.
///
/// Muzei's artwork screen is a full-screen image with pan and zoom; this is the
/// fork's equivalent, reached by a long press on the wallpaper page. It
/// deliberately does not reuse the Aves viewer: that one is the gallery, with its
/// own chrome, paging and info sheet, while this only answers "let me look at
/// this photo".
///
/// The artwork is laid out at its cover size, so at 1x it can already be panned
/// to the parts the wallpaper crops away (`BoxFit.cover` only crops at paint
/// time, which leaves nothing to pan).
class MuzeiWallpaperViewPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper/view';

  final Widget artwork;
  final double? aspectRatio;
  final String? title;

  const new({
    super.key,
    required this.artwork,
    this.aspectRatio,
    this.title,
  });

  @override
  State<MuzeiWallpaperViewPage> createState() => _MuzeiWallpaperViewPageState();
}

class _MuzeiWallpaperViewPageState extends State<MuzeiWallpaperViewPage> {
  final TransformationController _viewport = TransformationController();

  /// Geometry the viewport was last centered for; see [MuzeiWallpaperPage].
  (Size, Size)? _geometry;

  bool _chromeVisible = false;

  @override
  void initState() {
    super.initState();
    _setSystemUiVisible(false);
  }

  @override
  void dispose() {
    _setSystemUiVisible(true);
    _viewport.dispose();
    super.dispose();
  }

  /// Hides the system bars while looking at the photo, and restores them on any
  /// exit path (route pop, back gesture, or the whole page being disposed).
  static void _setSystemUiVisible(bool visible) {
    unawaited(AvesApp.showSystemUI(visible));
  }

  void _syncViewport(Size childSize, Size viewportSize) {
    final geometry = (childSize, viewportSize);
    if (_geometry == geometry) return;
    _geometry = geometry;
    final matrix = centeredCoverMatrix(childSize, viewportSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewport.value = matrix;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final viewportSize = constraints.biggest;
              final childSize = coverSizeFor(viewportSize, widget.aspectRatio);
              _syncViewport(childSize, viewportSize);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                child: InteractiveViewer(
                  transformationController: _viewport,
                  minScale: 1,
                  maxScale: 4,
                  constrained: false,
                  child: SizedBox(
                    width: childSize.width,
                    height: childSize.height,
                    child: widget.artwork,
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: .6), Colors.transparent],
                    ),
                  ),
                  child: Padding(
                    // The system bars are hidden here, so `SafeArea` would be
                    // zero; `viewPadding` keeps the chrome clear of a cutout.
                    padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
                    child: Row(
                      children: [
                        const BackButton(color: Colors.white),
                        Expanded(
                          child: Text(
                            widget.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
