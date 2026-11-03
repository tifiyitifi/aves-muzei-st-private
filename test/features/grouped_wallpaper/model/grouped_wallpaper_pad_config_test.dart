import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_pad_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The view page pad's config: fixed slots, the mandatory menu action, the
/// adaptive shape and the bottom-bar rule.
void main() {
  group('defaults', () {
    test('the historical staircase is kept, gaps included', () {
      const config = GroupedWallpaperPadConfig.defaultConfig;
      expect(config.slots, GroupedWallpaperPadConfig.defaultSlots);
      expect(config.slots[2], GroupedWallpaperPadAction.more);
      expect(config.slots[5], isNull);
      expect(config.slots[6], GroupedWallpaperPadAction.delete);
      expect(config.slots[7], isNull);
      expect(config.slots[8], isNull);
      expect(config.actionCount, 6);
      expect(config.fitToActions, isFalse);
      expect(config.bottomBar, isFalse);
    });

    test('a null slot list falls back to the historical layout', () {
      final config = GroupedWallpaperPadConfig.safe(slots: null);
      expect(config, GroupedWallpaperPadConfig.defaultConfig);
    });
  });

  group('sanitizing', () {
    test('duplicates are dropped and the list is padded to nine slots', () {
      final config = GroupedWallpaperPadConfig.safe(
        slots: const [
          GroupedWallpaperPadAction.more,
          GroupedWallpaperPadAction.more,
          GroupedWallpaperPadAction.delete,
          GroupedWallpaperPadAction.delete,
        ],
      );
      expect(config.slots, hasLength(9));
      expect(config.actions, [GroupedWallpaperPadAction.more, GroupedWallpaperPadAction.delete]);
      expect(config.slots.take(3), [GroupedWallpaperPadAction.more, null, GroupedWallpaperPadAction.delete]);
      expect(config.slots.skip(3), everyElement(isNull));
    });

    test('a config without the menu gains it at the historical slot', () {
      final config = GroupedWallpaperPadConfig.safe(
        slots: const [GroupedWallpaperPadAction.previousPhoto, null, null, GroupedWallpaperPadAction.delete],
      );
      expect(config.slots[GroupedWallpaperPadConfig.moreSlot], GroupedWallpaperPadAction.more);
      expect(config.actions, contains(GroupedWallpaperPadAction.more));
    });

    test('a full list without the menu gives up its last action', () {
      final config = GroupedWallpaperPadConfig.safe(
        slots: [
          for (final action in GroupedWallpaperPadAction.values)
            if (action != GroupedWallpaperPadAction.more) action,
        ],
      );
      expect(config.actionCount, GroupedWallpaperPadConfig.slotCount);
      expect(config.actions, contains(GroupedWallpaperPadAction.more));
    });

    test('the menu cannot be cleared through withSlot', () {
      const config = GroupedWallpaperPadConfig.defaultConfig;
      expect(config.withSlot(GroupedWallpaperPadConfig.moreSlot, null), config);
      expect(config.withSlot(0, null).slots[0], isNull);
    });

    test('adding an action fills the first empty slot and ignores duplicates', () {
      const config = GroupedWallpaperPadConfig.defaultConfig;
      final added = config.withActionAdded(GroupedWallpaperPadAction.share);
      expect(added.slots[5], GroupedWallpaperPadAction.share);
      expect(added.withActionAdded(GroupedWallpaperPadAction.share), added);
    });

    test('a full pad cannot take another action', () {
      final full = GroupedWallpaperPadConfig.safe(
        slots: [
          for (final action in GroupedWallpaperPadAction.values)
            if (action != GroupedWallpaperPadAction.more) action,
        ],
      );
      expect(full.firstEmptySlot, isNegative);
      expect(full.withActionAdded(GroupedWallpaperPadAction.more), full);
    });
  });

  group('bottom bar', () {
    test('is offered only with at most three actions', () {
      final config = GroupedWallpaperPadConfig.safe(
        slots: const [
          GroupedWallpaperPadAction.previousPhoto,
          GroupedWallpaperPadAction.nextPhoto,
          GroupedWallpaperPadAction.more,
        ],
        bottomBar: true,
      );
      expect(config.canUseBottomBar, isTrue);
      expect(config.usesBottomBar, isTrue);

      final four = config.withActionAdded(GroupedWallpaperPadAction.delete);
      expect(four.actionCount, 4);
      expect(four.bottomBar, isFalse, reason: 'a fourth action must not leave a bar that drops one');
      expect(four.usesBottomBar, isFalse);
    });

    test('stays off when a stored config asks for it with four actions', () {
      final config = GroupedWallpaperPadConfig.safe(
        slots: const [
          GroupedWallpaperPadAction.previousPhoto,
          GroupedWallpaperPadAction.nextPhoto,
          GroupedWallpaperPadAction.more,
          GroupedWallpaperPadAction.delete,
        ],
        bottomBar: true,
      );
      expect(config.bottomBar, isFalse);
    });
  });

  group('shape', () {
    GroupedWallpaperPadConfig withActions(int count) => GroupedWallpaperPadConfig.safe(
      slots: [
        for (var i = 0; i < count - 1; i++) GroupedWallpaperPadAction.values[i + 5],
        GroupedWallpaperPadAction.more,
      ],
    );

    test('square mode always uses the fixed 3x3 box', () {
      for (final count in [1, 4, 9]) {
        final config = withActions(count);
        expect(config.shapeFor(portrait: true), const GroupedWallpaperPadShape(3, 3));
        expect(config.shapeFor(portrait: false), const GroupedWallpaperPadShape(3, 3));
      }
    });

    test('adaptive mode follows the count and the screen orientation', () {
      GroupedWallpaperPadConfig config(int count) => withActions(count).copyWith(fitToActions: true);
      expect(config(1).shapeFor(portrait: true), const GroupedWallpaperPadShape(1, 1));
      expect(config(2).shapeFor(portrait: true), const GroupedWallpaperPadShape(1, 2));
      expect(config(2).shapeFor(portrait: false), const GroupedWallpaperPadShape(2, 1));
      expect(config(3).shapeFor(portrait: true), const GroupedWallpaperPadShape(2, 2));
      expect(config(4).shapeFor(portrait: false), const GroupedWallpaperPadShape(2, 2));
      expect(config(5).shapeFor(portrait: true), const GroupedWallpaperPadShape(2, 3));
      expect(config(6).shapeFor(portrait: false), const GroupedWallpaperPadShape(3, 2));
      expect(config(7).shapeFor(portrait: true), const GroupedWallpaperPadShape(3, 3));
      expect(config(9).shapeFor(portrait: false), const GroupedWallpaperPadShape(3, 3));
    });

    test('square cells keep the gaps, adaptive cells compact them', () {
      const config = GroupedWallpaperPadConfig.defaultConfig;
      final square = config.cellsFor(const GroupedWallpaperPadShape(3, 3));
      expect(square, config.slots);

      final adaptiveConfig = config.copyWith(fitToActions: true);
      final adaptive = adaptiveConfig.cellsFor(adaptiveConfig.shapeFor(portrait: true));
      // The default has 6 actions, which exactly fills the 2x3 portrait box.
      expect(adaptive, adaptiveConfig.actions);

      // With 5 actions the box keeps one trailing empty cell.
      final five = config.withSlot(6, null).copyWith(fitToActions: true);
      final padded = five.cellsFor(five.shapeFor(portrait: true));
      expect(padded, hasLength(6));
      expect(padded.last, isNull);
    });
  });

  group('serialization', () {
    test('a config round-trips', () {
      final config = GroupedWallpaperPadConfig.safe(
        slots: const [
          GroupedWallpaperPadAction.delete,
          null,
          GroupedWallpaperPadAction.more,
          GroupedWallpaperPadAction.share,
        ],
        fitToActions: true,
        bottomBar: false,
      );
      expect(GroupedWallpaperPadConfig.tryParse(config.encode()), config);
    });

    test('null, empty and corrupt values read as absent', () {
      expect(GroupedWallpaperPadConfig.tryParse(null), isNull);
      expect(GroupedWallpaperPadConfig.tryParse(''), isNull);
      expect(GroupedWallpaperPadConfig.tryParse('{'), isNull);
      expect(GroupedWallpaperPadConfig.tryParse('[]'), isNull);
    });

    test('unknown actions become empty slots and the menu is restored', () {
      final config = GroupedWallpaperPadConfig.fromJsonMap({
        'slots': ['delete', 'not-an-action', 'more', 42],
        'fitToActions': true,
        'bottomBar': true,
      });
      expect(config.slots[0], GroupedWallpaperPadAction.delete);
      expect(config.slots[1], isNull);
      expect(config.slots[2], GroupedWallpaperPadAction.more);
      expect(config.slots[3], isNull);
      expect(config.fitToActions, isTrue);
      expect(config.slots, hasLength(9));
    });
  });
}
