import 'package:aves/features/visible_range/view/visible_range_group_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which group the overflow's edit action edits.
///
/// The page is reachable without a selection, so the action has to name a group
/// in that state too instead of only after a long press.
void main() {
  test('with no selection the current group is edited', () {
    expect(
      visibleRangeEditGroupId(selecting: false, selectedItemCount: 0, selectedGroupIds: const [], currentGroupId: 'g1'),
      'g1',
    );
    expect(
      visibleRangeEditGroupId(selecting: true, selectedItemCount: 0, selectedGroupIds: const [], currentGroupId: 'g1'),
      'g1',
    );
  });

  test('one selected group is edited instead of the current one', () {
    expect(
      visibleRangeEditGroupId(selecting: true, selectedItemCount: 1, selectedGroupIds: const ['g2'], currentGroupId: 'g1'),
      'g2',
    );
  });

  test('a condition or a multi-group selection has no single group to edit', () {
    expect(
      visibleRangeEditGroupId(selecting: true, selectedItemCount: 1, selectedGroupIds: const [], currentGroupId: 'g1'),
      isNull,
    );
    expect(
      visibleRangeEditGroupId(selecting: true, selectedItemCount: 2, selectedGroupIds: const ['g2', 'g3'], currentGroupId: 'g1'),
      isNull,
    );
  });
}
