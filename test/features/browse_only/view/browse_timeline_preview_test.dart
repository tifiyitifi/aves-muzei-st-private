import 'package:aves/features/browse_only/view/browse_timeline_preview.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The strip is the way past the preview limit and the way to retry a failed
/// page: one button, two meanings, so the state has to pick the right one.
void main() {
  Widget app({required bool failed, required VoidCallback onContinue, required VoidCallback onRetry, int count = 12}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: BrowseTimelinePreview(count: count, failed: failed, onContinue: onContinue, onRetry: onRetry),
    ),
  );

  testWidgets('the strip states the rows the timeline shows', (tester) async {
    await tester.pumpWidget(app(failed: false, onContinue: () {}, onRetry: () {}, count: 4800));
    await tester.pump();

    final context = tester.element(find.byType(BrowseTimelinePreview));
    expect(find.text(context.l10n.browseOnlyTimelinePreview(4800)), findsOneWidget);
    expect(find.text(context.l10n.browseOnlyTimelineContinue), findsOneWidget);
  });

  testWidgets('at the limit the action asks for more rows', (tester) async {
    var continued = 0;
    var retried = 0;
    await tester.pumpWidget(app(failed: false, onContinue: () => continued++, onRetry: () => retried++));

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(continued, 1);
    expect(retried, 0);
  });

  testWidgets('after a failed page the action retries instead', (tester) async {
    var continued = 0;
    var retried = 0;
    await tester.pumpWidget(app(failed: true, onContinue: () => continued++, onRetry: () => retried++));

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(retried, 1);
    expect(continued, 0);
  });
}
