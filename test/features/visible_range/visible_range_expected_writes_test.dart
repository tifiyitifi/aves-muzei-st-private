import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/model/visible_range_write_back.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The save sheet names every place the confirmation writes: the groups that
/// receive the filters and the rules that are overwritten. Both halves come
/// from the same selection the save uses, so the promise cannot drift.
void main() {
  VisibleRangePinTarget pin(String id, {required VisibleRangePinTargetKind kind, required int number, required String name, VisibleRangeRuleKind? role}) => VisibleRangePinTarget(
        id: id,
        rangeId: 'range.$id',
        kind: kind,
        role: role,
        number: number,
        name: name,
      );

  VisibleRangeWriteBackTarget rule(String id, {required String owner, required int number, required VisibleRangeCandidateKind kind}) => VisibleRangeWriteBackTarget(
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

  final trips = pin('g1', kind: VisibleRangePinTargetKind.galleryGroup, number: 2, name: 'Trips');
  final outside = pin('o1', kind: VisibleRangePinTargetKind.outside, number: 0, name: '', role: VisibleRangeRuleKind.restriction);
  final wallpaper = pin('w1', kind: VisibleRangePinTargetKind.wallpaperGroup, number: 3, name: 'Home');
  final holiday = rule('u1', owner: 'Holiday', number: 1, kind: VisibleRangeCandidateKind.base);

  Future<String> summaryFor(
    WidgetTester tester, {
    List<VisibleRangePinTarget> pins = const [],
    Set<String> selectedPins = const {},
    List<VisibleRangeWriteBackTarget> rules = const [],
    Set<String> selectedUsages = const {},
    VisibleRangeRuleKind? forcedRole,
  }) async {
    late String summary;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            summary = visibleRangeExpectedWrites(
              context,
              pinTargets: pins,
              selectedPinIds: selectedPins,
              writeBackTargets: rules,
              selectedUsageIds: selectedUsages,
              forcedRole: forcedRole,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return summary;
  }

  testWidgets('nothing selected promises no write at all', (tester) async {
    expect(await summaryFor(tester), 'Nothing will be written.');
  });

  testWidgets('a selected group is named by its number and name', (tester) async {
    expect(await summaryFor(tester, pins: [trips], selectedPins: {trips.id}), 'Group 2 · Trips');
  });

  testWidgets('the outside pool keeps its role in the location line', (tester) async {
    expect(await summaryFor(tester, pins: [outside], selectedPins: {outside.id}), 'Outside groups · Restriction');
  });

  testWidgets('a wallpaper target is named as a wallpaper group', (tester) async {
    expect(await summaryFor(tester, pins: [wallpaper], selectedPins: {wallpaper.id}), 'Wallpaper groups · Home');
  });

  testWidgets('a forced role is named on a group pin', (tester) async {
    expect(
      await summaryFor(tester, pins: [trips], selectedPins: {trips.id}, forcedRole: VisibleRangeRuleKind.source),
      'Group 2 · Trips · Base range',
    );
  });

  testWidgets('groups are listed before write-back rules and only selected places appear', (tester) async {
    final unselected = pin('g2', kind: VisibleRangePinTargetKind.galleryGroup, number: 5, name: 'Pictures');
    final summary = await summaryFor(
      tester,
      pins: [trips, unselected],
      selectedPins: {trips.id},
      rules: [holiday],
      selectedUsages: {holiday.usageId},
    );
    expect(summary, 'Group 2 · Trips\nGroup 1 · Holiday · Base range');
    expect(summary, isNot(contains('Pictures')));
  });
}
