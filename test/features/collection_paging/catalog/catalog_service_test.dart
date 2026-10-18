import 'package:aves/features/collection_paging/catalog/catalog_service.dart';
import 'package:aves/model/source/tag.dart';
import 'package:flutter_test/flutter_test.dart';

/// Who sweeps the global backlog: the app worker, or the analysis service.
void main() {
  group('shouldDelegateCatalogToService', () {
    test('delegates a backlog that outlasts a visit', () {
      expect(shouldDelegateCatalogToService(canUseAnalysisService: true, uncatalogued: TagMixin.commitCountThreshold + 1), isTrue);
    });

    test('keeps a small backlog in the app', () {
      expect(shouldDelegateCatalogToService(canUseAnalysisService: true, uncatalogued: TagMixin.commitCountThreshold), isFalse);
      expect(shouldDelegateCatalogToService(canUseAnalysisService: true, uncatalogued: 0), isFalse);
    });

    test('never delegates when the service is unavailable', () {
      expect(shouldDelegateCatalogToService(canUseAnalysisService: false, uncatalogued: TagMixin.commitCountThreshold * 100), isFalse);
    });
  });
}
