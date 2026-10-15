import 'package:aves/model/settings/settings.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common.dart';

/// Guards the settings export/import key-space contract.
///
/// `export` filters the internal key space with `SettingKeys.isInternalKey`, and
/// `import` starts with `reset(includeInternalKeys: false)`, which applies the
/// same predicate. `isInternalKey` covers the whole `widget_*` family, so widget
/// configuration is deliberately outside the exported snapshot and must survive
/// that reset. Pulling it into the importer would make a restore silently reset
/// every home widget, so this pins the current, intended behaviour.
///
/// The full `import` is not exercised here: it ends in `sanitize`, which reads
/// the app-wide `device` singleton that tests do not initialize. The two steps
/// tested below are exactly the ones that key off the internal-key predicate.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  setUp(() async {
    await setUpServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  test('widget settings are excluded from export and preserved by the import reset', () async {
    const shapeKey = '${SettingKeys.widgetShapePrefixKey}1';
    const filtersKey = '${SettingKeys.widgetCollectionFiltersPrefixKey}1';
    settings.set(shapeKey, 'circle');
    settings.set(filtersKey, ['{"k":"v"}']);

    // A regular setting proves the export is otherwise populated, so the
    // widget exclusions below are meaningful rather than vacuous.
    settings.themeBrightness = AvesThemeBrightness.light;
    final exported = settings.export();
    expect(exported[SettingKeys.themeBrightnessKey], AvesThemeBrightness.light.name);

    expect(exported.keys, isNot(contains(shapeKey)), reason: 'internal widget keys must not be exported');
    expect(exported.keys, isNot(contains(filtersKey)));

    // The import's first step: drop every non-internal key, then re-apply the
    // snapshot (which never carried the widget keys in the first place).
    await settings.reset(includeInternalKeys: false);
    expect(settings.getString(shapeKey), 'circle', reason: 'an import must not reset widget configuration');
    expect(settings.getStringList(filtersKey), ['{"k":"v"}']);
  });
}
