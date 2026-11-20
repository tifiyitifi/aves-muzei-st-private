import 'package:aves/features/batch_ops/view/batch_share_done_snack_bar.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A share run ends at the share album, not in the system share sheet: the user
/// may want to review the copies first, or share only some of them.
void main() {
  testWidgets('offers to open the share album when a share run finishes', (tester) async {
    var viewed = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                batchShareDoneSnackBar(context, 2, onView: () => viewed++),
              ),
              child: const Text('run'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(find.text('2 copies ready to share'), findsOneWidget);
    expect(find.text('VIEW'), findsOneWidget);
    expect(viewed, 0, reason: 'the folder is offered, not opened');

    await tester.tap(find.text('VIEW'));
    await tester.pumpAndSettle();

    expect(viewed, 1);
  });
}
