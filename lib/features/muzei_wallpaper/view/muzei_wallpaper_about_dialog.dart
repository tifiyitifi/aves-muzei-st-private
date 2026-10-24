import 'dart:ui' as ui;

import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/aves_app.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/material.dart' as fm;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';

/// The Muzei release this port is written against (`muzei/version.properties`).
///
/// Fixed on purpose: it identifies the upstream source, not our build. Our own
/// app version is deliberately absent from this dialog, so a release that only
/// touches other features cannot read as "the wallpaper changed again".
const String muzeiPortedVersion = '3.7.1';

/// Shows the wallpaper's about dialog over a blurred, dimmed copy of the
/// artwork currently on screen.
///
/// [artwork] is the page's own image widget: the dialog must look like the
/// wallpaper behind it, so the crucially cheap option is to reuse that widget
/// instead of decoding the file a second time.
Future<void> showMuzeiWallpaperAbout(BuildContext context, {required Widget artwork}) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => _AboutDialog(artwork: artwork),
    transitionBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class _AboutDialog extends StatelessWidget {
  final Widget artwork;

  const new({required this.artwork});

  /// Our attribution, closing with the note that introduces the upstream text.
  ///
  /// The Muzei section is its own block, quoted verbatim from `about_body` in
  /// the Muzei sources (Apache-2.0); keeping it verbatim is both honest and the
  /// reason it reads nothing like the rest of the app.
  static String _ourMarkdown(BuildContext context) {
    final l10n = context.l10n;
    return [
      '**${l10n.muzeiWallpaperAbout}**',
      '',
      l10n.muzeiWallpaperAboutPorted,
      '',
      l10n.muzeiWallpaperAboutMuzeiSection,
    ].join('\n');
  }

  static String _muzeiMarkdown(BuildContext context) {
    final l10n = context.l10n;
    return [
      '**${l10n.muzeiWallpaperAboutMuzeiVersion(muzeiPortedVersion)}**',
      '',
      l10n.muzeiWallpaperAboutMuzeiBody,
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Over-scale the blurred copy: a blur samples beyond the widget bounds,
        // which would otherwise fade the edges to transparent.
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: Transform.scale(scale: 1.15, child: artwork),
          ),
        ),
        const Positioned.fill(child: ColoredBox(color: Colors.black54)),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
                child: Material(
                  type: MaterialType.card,
                  color: Colors.black.withValues(alpha: .62),
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: SingleChildScrollView(
                          // The markdown renderer reads the Flutter theme, which
                          // this tree does not provide, so it gets its own dark
                          // one: the backdrop behind the card is always dark.
                          child: fm.Theme(
                            data: fm.ThemeData.dark(useMaterial3: true),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                MarkdownBody(
                                  data: _ourMarkdown(context),
                                  selectable: true,
                                  onTapLink: (text, href, title) => AvesApp.launchUrl(href),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  // A thin, recessed line: the markdown rule is a
                                  // full-contrast slab that competes with the text.
                                  child: Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Colors.white.withValues(alpha: .10),
                                  ),
                                ),
                                MarkdownBody(
                                  data: _muzeiMarkdown(context),
                                  selectable: true,
                                  onTapLink: (text, href, title) => AvesApp.launchUrl(href),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                          icon: const Icon(AIcons.cancel, color: Colors.white70),
                          onPressed: () => Navigator.of(context).maybePop(),
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
    );
  }
}
