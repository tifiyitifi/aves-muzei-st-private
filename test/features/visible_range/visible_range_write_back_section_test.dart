import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_write_back.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_write_back_section.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The folded rule list and the summary outside the fold read one selection.
/// A tap on a row updates the summary in place, without rebuilding the rest of
/// the sheet or reading the store again.
void main() {
  VisibleRangeWriteBackTarget target(String id, {bool locked = false}) => VisibleRangeWriteBackTarget(
        usageId: id,
        rangeId: 'range.$id',
        targetId: id,
        kind: VisibleRangeCandidateKind.restriction,
        isGallery: true,
        number: 2,
        ownerName: 'Trips',
        label: '',
        locked: locked,
      );

  final trips = target('u1');

  Future<void> pumpPair(WidgetTester tester, {required ValueNotifier<Set<String>> selected, required List<VisibleRangeWriteBackTarget> targets}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VisibleRangeExpectedWrites(
                pinTargets: const [],
                selectedPinIds: const {},
                writeBackTargets: targets,
                selectedUsageIds: selected,
              ),
              VisibleRangeWriteBackList(
                targets: targets,
                selectedIds: selected,
                onToggle: (id) {
                  final next = {...selected.value, id};
                  selected.value = next;
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a ticked rule reaches the summary without a sheet rebuild', (tester) async {
    final selected = ValueNotifier<Set<String>>(<String>{});
    await pumpPair(tester, selected: selected, targets: [trips]);

    final summary = find.byKey(const Key('visibleRangeExpectedWrites'));
    expect(tester.widget<Text>(summary).data, 'Nothing will be written.');

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(summary).data, 'Group 2 · Trips · Restriction');
  });

  testWidgets('a locked rule cannot be selected', (tester) async {
    final selected = ValueNotifier<Set<String>>(<String>{});
    await pumpPair(tester, selected: selected, targets: [target('u1', locked: true)]);

    final row = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(row.onChanged, isNull);
    expect(tester.widget<Text>(find.byKey(const Key('visibleRangeExpectedWrites'))).data, 'Nothing will be written.');
  });

  testWidgets('an empty rule pool says so only inside the folded list', (tester) async {
    final selected = ValueNotifier<Set<String>>(<String>{});
    await pumpPair(tester, selected: selected, targets: const []);

    expect(find.text('No rule has opened a media set yet.'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('visibleRangeExpectedWrites'))).data, 'Nothing will be written.');
  });
}
