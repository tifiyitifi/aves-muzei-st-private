import 'dart:async';

import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_history_limit_dialog.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Regression: the dialog used to dispose its `TextEditingController` as soon as
/// `showDialog` returned, while the route was still animating out. The rebuilding
/// `TextField` then used a disposed controller, which threw and turned the whole
/// page into an error screen (the "white screen" report).
void main() {
  Widget wrap(void Function(BuildContext context) onOpen) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => onOpen(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

  testWidgets('confirming the limit closes the dialog without using a disposed controller', (tester) async {
    int? result;
    await tester.pumpWidget(
      wrap((context) => unawaited(showGroupedWallpaperHistoryLimitDialog(context, limit: 200).then((value) => result = value))),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '50');
    await tester.tap(find.text('OK'));
    // Pumping through the exit animation is what used to trip the disposed
    // controller, so the assertion below has to come after it settles.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, 50);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('cancelling the limit closes the dialog without using a disposed controller', (tester) async {
    await tester.pumpWidget(wrap((context) => unawaited(showGroupedWallpaperHistoryLimitDialog(context, limit: 200))));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsNothing);
  });
}
