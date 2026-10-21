import 'package:aves/app_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppMode.isPicking', () {
    test('covers every mode that returns a choice to its caller', () {
      const picking = {
        AppMode.pickCollectionFiltersExternal,
        AppMode.pickSingleMediaExternal,
        AppMode.pickMultipleMediaExternal,
        AppMode.pickFilteredMediaInternal,
        AppMode.pickUnfilteredMediaInternal,
        AppMode.pickFilterInternal,
      };
      for (final mode in AppMode.values) {
        expect(mode.isPicking, picking.contains(mode), reason: '$mode');
      }
    });

    test('a browse-only surface is not replaced while picking', () {
      // The browser has nothing selectable and no confirm: a pick that arrives
      // during the first import must keep the collection surface.
      expect(AppMode.main.isPicking, isFalse);
      expect(AppMode.view.isPicking, isFalse);
      expect(AppMode.pickMultipleMediaExternal.isPicking, isTrue);
      expect(AppMode.pickCollectionFiltersExternal.isPicking, isTrue);
    });
  });
}
