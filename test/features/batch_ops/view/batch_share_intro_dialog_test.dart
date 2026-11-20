import 'dart:async';

import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/batch_ops/view/batch_share_flow.dart';
import 'package:aves/features/batch_ops/view/batch_share_intro_dialog.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../common.dart';

/// Copy & share writes a temporary folder, so the first run explains it before
/// anything is configured, and the explainer can open its settings page.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  Widget wrap(void Function(BuildContext context) onPressed) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => onPressed(context),
              child: const Text('share'),
            ),
          ),
        ),
      );

  testWidgets('explains the folder and offers settings before the sheet', (tester) async {
    await tester.pumpWidget(wrap((context) => unawaited(startBatchShare(context, {_entry()}))));

    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();

    expect(find.text('Sharing works on a copy'), findsOneWidget);
    expect(find.textContaining('not a backup'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Copy & share'), findsNothing, reason: 'the sheet waits for the explainer');

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Sharing works on a copy'), findsNothing);
    expect(find.text('Copy & share'), findsWidgets, reason: 'the sheet opens once the explainer is read');
  });

  testWidgets('dismissing the explainer does not continue', (tester) async {
    await tester.pumpWidget(wrap((context) => unawaited(startBatchShare(context, {_entry()}))));

    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();
    // The barrier is the "not now" path: reading the explainer is not consent.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Sharing works on a copy'), findsNothing);
    expect(find.text('Copy & share'), findsNothing);
  });

  testWidgets('reports the retention the explainer will honour', (tester) async {
    await batchSettings.setShareRetentionDays(BatchSettings.defaultShareRetentionDays);
    await tester.pumpWidget(
      wrap((context) => unawaited(showBatchShareIntroDialog(context))),
    );

    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();
    expect(find.textContaining('older than 7 days'), findsOneWidget);

    // The dialog can open the settings page, so its sentence has to follow a
    // change made there without being closed and reopened.
    await batchSettings.setShareRetentionDays(0);
    await tester.pumpAndSettle();

    expect(find.textContaining('older than'), findsNothing);
    expect(find.textContaining('copies stay until you delete them'), findsOneWidget);

    await batchSettings.setShareRetentionDays(BatchSettings.defaultShareRetentionDays);
  });
}

AvesEntry _entry() {
  return AvesEntry(
    id: 1,
    uri: 'content://media/1',
    path: '/storage/emulated/0/DCIM/Camera/IMG_0001.jpg',
    contentId: 1,
    pageId: null,
    sourceMimeType: 'image/jpeg',
    width: 10,
    height: 20,
    sourceRotationDegrees: 0,
    sizeBytes: 5,
    sourceTitle: 'IMG_0001.jpg',
    dateAddedSecs: 1,
    dateModifiedMillis: 2,
    sourceDateTakenMillis: 3,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );
}
