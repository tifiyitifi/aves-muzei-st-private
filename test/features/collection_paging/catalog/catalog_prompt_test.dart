import 'package:aves/features/collection_paging/catalog/catalog_prompt.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../../common.dart';

/// The catalog question: when it is worth asking, that it is asked once per
/// session, and what each answer does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    await setUpAllServices();
  });

  group('CatalogPrompt', () {
    late CatalogPrompt prompt;

    setUp(() => prompt = CatalogPrompt());

    tearDown(() => prompt.resetSession());

    test('asks only for a large backlog', () {
      expect(prompt.shouldAsk(askBeforeCatalog: true, uncatalogued: CatalogPrompt.threshold), isFalse);
      expect(prompt.shouldAsk(askBeforeCatalog: true, uncatalogued: CatalogPrompt.threshold + 1), isTrue);
    });

    test('never asks a user who opted out', () {
      expect(prompt.shouldAsk(askBeforeCatalog: false, uncatalogued: CatalogPrompt.threshold * 10), isFalse);
    });

    test('asks at most once per session, answered or not', () {
      prompt.markAsked(5000);
      expect(prompt.pending.value, 5000);
      expect(prompt.shouldAsk(askBeforeCatalog: true, uncatalogued: 10000), isFalse);

      prompt.resolve();
      expect(prompt.pending.value, isNull);
      expect(prompt.shouldAsk(askBeforeCatalog: true, uncatalogued: 10000), isFalse);
    });
  });

  group('applyCatalogPromptAnswer', () {
    setUp(() => collectionPagingPrefs.setAskBeforeCatalog(true));
    tearDown(() => collectionPagingPrefs.setAskBeforeCatalog(true));

    test('catalogue now sweeps and keeps asking', () async {
      expect(await applyCatalogPromptAnswer(CatalogPromptAnswer.catalogueNow), isTrue);
      expect(collectionPagingPrefs.askBeforeCatalog, isTrue);
    });

    test('later sweeps nothing and keeps asking', () async {
      expect(await applyCatalogPromptAnswer(CatalogPromptAnswer.notNow), isFalse);
      expect(collectionPagingPrefs.askBeforeCatalog, isTrue);
    });

    test('always sweeps and stops asking, reversibly', () async {
      expect(await applyCatalogPromptAnswer(CatalogPromptAnswer.alwaysCatalogue), isTrue);
      expect(collectionPagingPrefs.askBeforeCatalog, isFalse);

      // The settings surface can turn it back on, so the choice is not a trap.
      await collectionPagingPrefs.setAskBeforeCatalog(true);
      expect(collectionPagingPrefs.askBeforeCatalog, isTrue);
    });
  });
}
