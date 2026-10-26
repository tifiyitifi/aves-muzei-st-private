import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Section headers describe the group itself: the base group shows how many
/// choices it offers, and the rule groups show `active/total`.
void main() {
  Future<VisibleRangeSectionKey> keyFor(
    WidgetTester tester,
    VisibleRangeCandidateKind kind, {
    String countText = '',
    bool supplementsOutside = true,
  }) async {
    late VisibleRangeSectionKey key;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            key = VisibleRangeSectionKey(context, kind, countText: countText, supplementsOutside: supplementsOutside);
            return const SizedBox();
          },
        ),
      ),
    );
    return key;
  }

  testWidgets('the base header advertises its displayed choice count', (tester) async {
    final key = await keyFor(tester, VisibleRangeCandidateKind.base, countText: '19');
    expect(key.title, 'base range (exclusive) 19');
  });

  testWidgets('rule headers show active over total', (tester) async {
    expect((await keyFor(tester, VisibleRangeCandidateKind.restriction, countText: '2/12')).title, 'additional restrictions 2/12');
    expect((await keyFor(tester, VisibleRangeCandidateKind.supplement, countText: '0/12')).title, 'supplements outside the base 0/12');
    expect(
      (await keyFor(tester, VisibleRangeCandidateKind.supplement, countText: '1/12', supplementsOutside: false)).title,
      'supplements inside the restrictions 1/12',
    );
  });

  testWidgets('headers drop the small-caps styling', (tester) async {
    final style = (await keyFor(tester, VisibleRangeCandidateKind.base, countText: '3')).titleStyle!;
    expect(style.fontFeatures, isEmpty);
    expect(style.letterSpacing, 0);
    expect(style.fontWeight, FontWeight.normal);
  });

  testWidgets('a header without a count stays a bare group name', (tester) async {
    expect((await keyFor(tester, VisibleRangeCandidateKind.base)).title, 'base range (exclusive)');
  });
}
