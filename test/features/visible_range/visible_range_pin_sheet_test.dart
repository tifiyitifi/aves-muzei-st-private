import 'package:aves/features/visible_range/view/visible_range_pin_sheet.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The save sheet's advanced options. Role is a per-save choice, append and
/// replace are two named buttons, and the write-back rules live inside the
/// collapsible section while its expected destinations stay visible.
void main() {
  // A distinct key makes a reopen a new sheet state, not a rebuild of the old
  // one: Flutter would otherwise reuse the State because the widget type matches.
  var generation = 0;

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VisibleRangePinSheet(key: ValueKey(generation++), filters: const {}, initialName: 'Pinned', initialDescription: 'now'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expandOptions(WidgetTester tester) async {
    await tester.tap(find.text('Injection options'));
    await tester.pumpAndSettle();
  }

  Future<void> tapLabel(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('the role starts from the automatic split on every open', (tester) async {
    await pumpSheet(tester);
    await expandOptions(tester);
    expect(find.text('Split automatically'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);

    // A custom role affects this save only; reopening the sheet resets it.
    await tapLabel(tester, 'Custom');
    await tapLabel(tester, 'Restriction');
    expect(find.text('Restriction'), findsOneWidget);

    await pumpSheet(tester);
    await expandOptions(tester);
    expect(find.text('Split automatically'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Restriction'), findsNothing);
  });

  testWidgets('the custom role button opens the role menu on every tap', (tester) async {
    await pumpSheet(tester);
    await expandOptions(tester);
    await tapLabel(tester, 'Custom');
    await tapLabel(tester, 'Base range');

    // The button now reads as the chosen role, but a second tap asks again.
    await tapLabel(tester, 'Base range');
    expect(find.text('Restriction'), findsOneWidget);
    expect(find.text('Supplement'), findsOneWidget);
  });

  testWidgets('the existing conditions choice is two named buttons, not a switch', (tester) async {
    await pumpSheet(tester);
    await expandOptions(tester);
    expect(find.text('Append'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    // Only the remember option still uses a switch.
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('the remember option names what it stores', (tester) async {
    await pumpSheet(tester);
    await expandOptions(tester);
    expect(find.text('Remember the injection option'), findsOneWidget);
    expect(find.textContaining('not remembered'), findsOneWidget);
  });

  testWidgets('the expected write locations stay outside the collapsible section', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Expected write locations'), findsOneWidget);
    expect(find.text('No rule has opened a media set yet.'), findsOneWidget);
  });
}
