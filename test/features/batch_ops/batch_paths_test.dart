import 'package:aves/features/batch_ops/model/batch_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batch results path', () {
    test('recognizes the results folder on any volume and case', () {
      expect(isBatchResultsPath('/storage/emulated/0/Pictures/aves_batch_results'), isTrue);
      expect(isBatchResultsPath(r'/storage/emulated/0/Pictures\aves_batch_results'), isTrue);
      expect(isBatchResultsPath('/storage/emulated/95/Pictures/aves_batch_results'), isTrue);
    });

    test('recognizes a subfolder of the results tree', () {
      expect(isBatchResultsPath('/storage/emulated/0/Pictures/aves_batch_results/2026'), isTrue);
    });

    test('does not match a sibling folder with the same prefix', () {
      expect(isBatchResultsPath('/storage/emulated/0/Pictures/aves_batch_results_old'), isFalse);
      expect(isBatchResultsPath('/storage/emulated/0/Pictures/aves_batch'), isFalse);
      expect(isBatchResultsPath('/storage/emulated/0/DCIM/Camera'), isFalse);
    });

    test('recognizes the relative output spec exactly', () {
      expect(isBatchResultsRelativePath(batchResultsRelativeRoot), isTrue);
      expect(isBatchResultsRelativePath('Pictures/aves_batch_results'), isTrue);
      expect(isBatchResultsRelativePath('/Pictures/aves_batch_results'), isTrue);
      expect(isBatchResultsRelativePath('Pictures/aves_share_batch'), isFalse);
      expect(isBatchResultsRelativePath('Pictures/aves_batch_results_old'), isFalse);
    });
  });
}
