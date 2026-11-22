import 'package:aves/features/known_issues/view/known_issues_page.dart';
import 'package:aves/features/known_issues/view/known_issues_section.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The accepted-limitations list has one source and two readers: the About
/// section and the Advanced settings page. Both must show the same entries, and
/// the numbering must stay a widget of its own so an RTL paragraph does not
/// swallow it.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  Future<List<String>> entriesOf(WidgetTester tester) async {
    late List<String> entries;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            entries = knownIssues(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return entries;
  }

  testWidgets('the shared list holds no blank or repeated entry', (tester) async {
    final entries = await entriesOf(tester);

    expect(entries, isNotEmpty);
    expect(entries.toSet(), hasLength(entries.length), reason: 'an entry copied twice documents the same limitation twice');
    expect(entries.every((entry) => entry.trim().isNotEmpty), isTrue);
  });

  testWidgets('the body shared with About renders every entry', (tester) async {
    final entries = await entriesOf(tester);

    // The body is a plain Column, so it needs a scroll parent to lay out.
    await tester.pumpWidget(wrap(const SingleChildScrollView(child: Builder(builder: KnownIssuesSection.buildBody))));

    for (final entry in entries) {
      expect(find.text(entry), findsOneWidget);
    }
  });

  testWidgets('the known-issues page renders every entry, numbered', (tester) async {
    final entries = await entriesOf(tester);
    // The page is a lazy list; grow the viewport so every row is built.
    await tester.binding.setSurfaceSize(const Size(600, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(const KnownIssuesPage()));

    for (var index = 0; index < entries.length; index++) {
      expect(find.text(entries[index]), findsOneWidget);
      expect(find.text('${index + 1}.'), findsOneWidget);
    }
  });

  testWidgets('an entry keeps its number out of its own text', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => KnownIssuesSection.knownIssueRow(context, 1, 'a limitation'),
        ),
      ),
    );

    // Under RTL a concatenated "2. a limitation" would move the number to the
    // wrong side of the paragraph, so the number is its own widget.
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('a limitation'), findsOneWidget);
  });
}
