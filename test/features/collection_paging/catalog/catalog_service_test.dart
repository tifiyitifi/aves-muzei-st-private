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

  group('shouldPreemptCatalogService', () {
    test('preempts a view at least one commit batch wide', () {
      expect(shouldPreemptCatalogService(serviceDelegated: true, scopedUncatalogued: TagMixin.commitCountThreshold), isTrue);
      expect(shouldPreemptCatalogService(serviceDelegated: true, scopedUncatalogued: TagMixin.commitCountThreshold + 1), isTrue);
    });

    test('leaves a view smaller than a commit batch to the service', () {
      expect(shouldPreemptCatalogService(serviceDelegated: true, scopedUncatalogued: TagMixin.commitCountThreshold - 1), isFalse);
      expect(shouldPreemptCatalogService(serviceDelegated: true, scopedUncatalogued: 0), isFalse);
    });

    test('never preempts when the service does not own the backlog', () {
      expect(shouldPreemptCatalogService(serviceDelegated: false, scopedUncatalogued: TagMixin.commitCountThreshold * 100), isFalse);
    });
  });
}
