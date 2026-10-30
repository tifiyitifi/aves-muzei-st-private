import 'package:aves/features/muzei_wallpaper/view/wallpaper_artwork_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The two artwork screens share one panel, so both lines that name the photo
/// must carry the same two gestures: a tap views it, a long press hands it to
/// another app.
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    String? title,
    String? subtitle,
    String? status,
    required VoidCallback onViewArtwork,
    required VoidCallback onOpenWith,
    List<Widget> actions = const [],
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: WallpaperArtworkPanel(
                title: title,
                subtitle: subtitle,
                status: status,
                onViewArtwork: onViewArtwork,
                onOpenWith: onOpenWith,
                actions: actions,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('shows the title, the status and the interactive line', (tester) async {
    await pumpPanel(
      tester,
      title: 'IMG_0001',
      status: 'Source is empty',
      subtitle: 'Pictures · 767 photos',
      onViewArtwork: () {},
      onOpenWith: () {},
    );

    expect(find.text('IMG_0001'), findsOneWidget);
    expect(find.text('Source is empty'), findsOneWidget);
    expect(find.text('Pictures · 767 photos'), findsOneWidget);
  });

  testWidgets('tapping the title views the artwork', (tester) async {
    var viewed = 0;
    await pumpPanel(tester, title: 'IMG_0001', subtitle: 'Pictures · 767 photos', onViewArtwork: () => viewed++, onOpenWith: () {});

    await tester.tap(find.text('IMG_0001'));
    await tester.pump();

    expect(viewed, 1);
  });

  testWidgets('long pressing the title opens with another app', (tester) async {
    var opened = 0;
    await pumpPanel(tester, title: 'IMG_0001', subtitle: 'Pictures · 767 photos', onViewArtwork: () {}, onOpenWith: () => opened++);

    await tester.longPress(find.text('IMG_0001'));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('the interactive line carries both gestures', (tester) async {
    var viewed = 0;
    var opened = 0;
    await pumpPanel(tester, title: 'IMG_0001', subtitle: 'Pictures · 767 photos', onViewArtwork: () => viewed++, onOpenWith: () => opened++);

    await tester.tap(find.text('Pictures · 767 photos'));
    await tester.pump();
    expect(viewed, 1);

    await tester.longPress(find.text('Pictures · 767 photos'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('renders the trailing actions', (tester) async {
    await pumpPanel(
      tester,
      title: 'IMG_0001',
      onViewArtwork: () {},
      onOpenWith: () {},
      actions: const [Icon(Icons.more_horiz)],
    );

    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
  });
}
