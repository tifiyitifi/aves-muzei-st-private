import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A group card states its range in one line. A bundled group's base is spelled
/// exactly like the group, so repeating it would push the image count off a
/// narrow card; only a base that differs is named. Supplements never count,
/// because they only add back what the base already allowed.
void main() {
  Future<String> summary(WidgetTester tester, {required VisibleRange? range, String groupName = '@wallpaperGroupDefaultPictures', bool isNone = false}) async {
    late String result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            result = visibleRangeGroupSummary(context, range: range, groupName: groupName, isNone: isNone);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  VisibleRange range({String baseName = '', Set<CollectionFilter> baseFilters = const {}, List<VisibleRangeRule> rules = const []}) => VisibleRange(
        id: 'wallpaper.group.1.range',
        scope: VisibleRangeScope.wallpaper,
        ownerId: '1',
        baseName: baseName,
        baseFilters: baseFilters,
        rules: rules,
      );

  VisibleRangeRule rule(String id, VisibleRangeRuleKind kind, {bool active = true}) => VisibleRangeRule(
        id: id,
        rangeId: 'wallpaper.group.1.range',
        kind: kind,
        position: 0,
        filters: {MimeFilter.image},
        active: active,
      );

  const picturesBase = '@wallpaperGroupDefaultPictures';

  testWidgets('a base named like its group is not repeated', (tester) async {
    expect(await summary(tester, range: range(baseName: picturesBase, baseFilters: {MimeFilter.image})), '');
  });

  testWidgets('active restrictions are counted', (tester) async {
    final value = range(
      baseName: picturesBase,
      baseFilters: {MimeFilter.image},
      rules: [rule('r1', VisibleRangeRuleKind.restriction), rule('r2', VisibleRangeRuleKind.restriction, active: false)],
    );
    expect(await summary(tester, range: value), '+1');
  });

  testWidgets('supplements are never counted', (tester) async {
    final value = range(
      baseName: picturesBase,
      baseFilters: {MimeFilter.image},
      rules: [rule('r1', VisibleRangeRuleKind.supplement)],
    );
    expect(await summary(tester, range: value), '');
  });

  testWidgets('a renamed group still names its range', (tester) async {
    final value = range(baseName: picturesBase, baseFilters: {MimeFilter.image}, rules: [rule('r1', VisibleRangeRuleKind.restriction)]);
    expect(await summary(tester, range: value, groupName: 'Trips'), 'Pictures +1');
  });

  testWidgets('an unrestricted base is not named', (tester) async {
    final value = range(rules: [rule('r1', VisibleRangeRuleKind.restriction)]);
    expect(await summary(tester, range: value, groupName: 'Trips'), '+1');
  });

  testWidgets('an unnamed base falls back to its filters', (tester) async {
    final value = range(baseFilters: {MimeFilter.image});
    expect(await summary(tester, range: value, groupName: 'Trips'), 'Image');
  });

  testWidgets('group 0 has no range to describe', (tester) async {
    expect(await summary(tester, range: null, groupName: 'none', isNone: true), '');
  });
}
