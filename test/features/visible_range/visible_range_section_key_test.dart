import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Section headers name the part of the traffic the tiles edit: the group's own
/// base sources, the scope-wide outside restrictions/supplements, or the mutually
/// exclusive groups themselves.
void main() {
  Future<VisibleRangeSectionKey> keyFor(
    WidgetTester tester,
    VisibleRangeCandidateKind kind, {
    String countText = '',
    bool outside = false,
  }) async {
    late VisibleRangeSectionKey key;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            key = VisibleRangeSectionKey(context, kind, countText: countText, outside: outside);
            return const SizedBox();
          },
        ),
      ),
    );
    return key;
  }

  testWidgets('the base header advertises its displayed choice count', (tester) async {
    final key = await keyFor(tester, VisibleRangeCandidateKind.base, countText: '3');
    expect(key.title, 'base sources 3');
  });

  testWidgets('rule headers show active over total', (tester) async {
    expect((await keyFor(tester, VisibleRangeCandidateKind.restriction, countText: '2/12')).title, 'restrictions 2/12');
    expect((await keyFor(tester, VisibleRangeCandidateKind.supplement, countText: '0/12')).title, 'supplements 0/12');
  });

  testWidgets('outside headers name the shared pool', (tester) async {
    expect((await keyFor(tester, VisibleRangeCandidateKind.restriction, countText: '1/3', outside: true)).title, 'outside restrictions 1/3');
    expect((await keyFor(tester, VisibleRangeCandidateKind.supplement, countText: '0/2', outside: true)).title, 'outside supplements 0/2');
  });

  testWidgets('headers drop the small-caps styling', (tester) async {
    final style = (await keyFor(tester, VisibleRangeCandidateKind.base, countText: '3')).titleStyle!;
    expect(style.fontFeatures, isEmpty);
    expect(style.letterSpacing, 0);
    expect(style.fontWeight, FontWeight.normal);
  });

  testWidgets('a header without a count stays a bare group name', (tester) async {
    expect((await keyFor(tester, VisibleRangeCandidateKind.base)).title, 'base sources');
  });

  testWidgets('the Chinese base header names the role without an exclusivity note', (tester) async {
    late VisibleRangeSectionKey key;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [...AppLocalizations.localizationsDelegates, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            key = VisibleRangeSectionKey(context, VisibleRangeCandidateKind.base);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(key.title, '基础来源');
    expect(key.title, isNot(contains('（')));
  });

  test('the base count skips the unrestricted choice', () {
    final candidates = [
      VisibleRangeCandidate.unrestricted,
      const VisibleRangeCandidate(id: 'src.a', kind: VisibleRangeCandidateKind.base, filters: {}, active: true),
      const VisibleRangeCandidate(id: 'src.b', kind: VisibleRangeCandidateKind.base, filters: {}),
    ];
    expect(visibleRangeSectionCountText(VisibleRangeCandidateKind.base, candidates), '1/2');
  });

  test('a rule section counts switched-off rules but an empty section has no count', () {
    final candidates = [
      const VisibleRangeCandidate(id: 'rule.a', kind: VisibleRangeCandidateKind.restriction, filters: {}, active: true),
      const VisibleRangeCandidate(id: 'rule.b', kind: VisibleRangeCandidateKind.restriction, filters: {}),
    ];
    expect(visibleRangeSectionCountText(VisibleRangeCandidateKind.restriction, candidates), '1/2');
    expect(visibleRangeSectionCountText(VisibleRangeCandidateKind.restriction, const <VisibleRangeCandidate>[]), isEmpty);
    expect(
      visibleRangeSectionCountText(
        VisibleRangeCandidateKind.restriction,
        [const VisibleRangeCandidate(id: 'empty', kind: VisibleRangeCandidateKind.restriction, filters: {}, placeholder: true)],
      ),
      isEmpty,
    );
  });

  testWidgets('the groups header names the sentinel list', (tester) async {
    late VisibleRangeGroupSectionKey key;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            key = VisibleRangeGroupSectionKey(context, countText: '4');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(key.title, 'groups 4');
  });
}
