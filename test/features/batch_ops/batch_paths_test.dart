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

  group('batch share path', () {
    test('recognizes the share folder on any volume and case', () {
      expect(isBatchSharePath('/storage/emulated/0/Pictures/aves_share'), isTrue);
      expect(isBatchSharePath(r'/storage/emulated/0/Pictures\aves_share'), isTrue);
      expect(isBatchSharePath('/storage/emulated/95/Pictures/aves_share'), isTrue);
    });

    test('recognizes a subfolder of the share tree', () {
      expect(isBatchSharePath('/storage/emulated/0/Pictures/aves_share/2026'), isTrue);
    });

    test('does not match a sibling folder with the same prefix', () {
      expect(isBatchSharePath('/storage/emulated/0/Pictures/aves_share_old'), isFalse);
      expect(isBatchSharePath('/storage/emulated/0/Pictures/aves_shared'), isFalse);
      expect(isBatchSharePath('/storage/emulated/0/DCIM/Camera'), isFalse);
    });

    test('does not treat the share folder as batch results', () {
      expect(isBatchResultsPath('/storage/emulated/0/Pictures/aves_share'), isFalse);
      expect(isBatchSharePath('/storage/emulated/0/Pictures/aves_batch_results'), isFalse);
      expect(isBatchResultsRelativePath(batchShareRelativeRoot), isFalse);
    });

    test('recognizes the share relative output spec exactly', () {
      expect(isBatchShareRelativePath(batchShareRelativeRoot), isTrue);
      expect(isBatchShareRelativePath('Pictures/aves_share'), isTrue);
      expect(isBatchShareRelativePath('/Pictures/aves_share'), isTrue);
      expect(isBatchShareRelativePath('Pictures/aves_share_old'), isFalse);
      expect(isBatchShareRelativePath(batchResultsRelativeRoot), isFalse);
    });
  });
}
