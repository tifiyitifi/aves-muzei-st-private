import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_write_back.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The save sheet keeps its write-back rules inside the advanced section, but
/// still names where the confirmation writes outside it.
void main() {
  VisibleRangeWriteBackTarget target(String id, {required String owner, required int number, required VisibleRangeCandidateKind kind}) => VisibleRangeWriteBackTarget(
        usageId: id,
        rangeId: 'range.$id',
        targetId: id,
        kind: kind,
        isGallery: true,
        number: number,
        ownerName: owner,
        label: '',
        locked: false,
      );

  final trips = target('u1', owner: 'Trips', number: 1, kind: VisibleRangeCandidateKind.restriction);
  final holiday = target('u2', owner: 'Holiday', number: 2, kind: VisibleRangeCandidateKind.base);

  Future<String> summaryFor(WidgetTester tester, List<VisibleRangeWriteBackTarget> targets, Set<String> selected) async {
    late String summary;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            summary = visibleRangeWriteBackSummary(context, targets: targets, selectedIds: selected);
            return const SizedBox();
          },
        ),
      ),
    );
    return summary;
  }

  testWidgets('an empty pool says there is no rule to write back to', (tester) async {
    expect(await summaryFor(tester, const [], const {}), 'No rule has opened a media set yet.');
  });

  testWidgets('an unselected list promises no write-back', (tester) async {
    expect(await summaryFor(tester, [trips, holiday], const {}), 'Nothing will be written back.');
  });

  testWidgets('the summary names every selected target and only those', (tester) async {
    final summary = await summaryFor(tester, [trips, holiday], {trips.usageId});
    expect(summary, contains('Group 1'));
    expect(summary, contains('Trips'));
    expect(summary, isNot(contains('Holiday')));
  });

  testWidgets('several selected targets are all named', (tester) async {
    final summary = await summaryFor(tester, [trips, holiday], {trips.usageId, holiday.usageId});
    expect(summary, contains('Trips'));
    expect(summary, contains('Holiday'));
  });
}
