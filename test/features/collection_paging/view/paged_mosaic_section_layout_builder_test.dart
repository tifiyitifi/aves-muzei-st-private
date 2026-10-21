import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/collection_paging/view/paged_mosaic_section_layout_builder.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/source/section_keys.dart';
import 'package:aves/widgets/common/grid/sections/list_layout.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The mosaic packing against a windowed section: a section whose ratio channel
/// has not landed yet must still lay out, instead of crashing the sliver (the
/// blank frame every switch to the mosaic layout used to show).
void main() {
  const key = EntryDateSectionKey(year: 2024, month: 1);
  final skeleton = SkeletonEntry.forMonth(2024, 1, key);

  SectionedListLayout<AvesEntry> buildLayout({
    required BuildContext context,
    required List<AvesEntry> rows,
    required List<double>? Function(SectionKey key) ratioResolver,
  }) {
    return PagedMosaicSectionLayoutBuilder<AvesEntry>(
      sections: {key: rows},
      showHeaders: true,
      getHeaderExtent: (context, sectionKey) => 40,
      buildHeader: (context, sectionKey, headerExtent) => SizedBox(height: headerExtent),
      scrollableWidth: 400,
      tileLayout: TileLayout.mosaic,
      columnCount: 4,
      spacing: 4,
      horizontalPadding: 2,
      tileWidth: 96,
      tileHeight: 96,
      tileBuilder: (entry, tileSize) => SizedBox.fromSize(size: tileSize),
      tileAnimationDelay: Duration.zero,
      ratioResolver: ratioResolver,
      coverRatioResolver: (entry) => entry.displayAspectRatio,
    ).updateLayouts(context);
  }

  /// Builds every child the section owns, the way the sliver would.
  Future<void> pumpSection(WidgetTester tester, SectionedListLayout<AvesEntry> layout) async {
    final sectionLayout = layout.sectionLayouts.single;
    for (var index = sectionLayout.firstIndex; index <= sectionLayout.lastIndex; index++) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (context) => sectionLayout.builder(context, index)),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'section child $index must build');
    }
  }

  testWidgets('a section packs itself while its ratio channel is missing', (tester) async {
    late SectionedListLayout<AvesEntry> layout;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (context) {
          layout = buildLayout(context: context, rows: [skeleton, skeleton], ratioResolver: (_) => null);
          return const SizedBox();
        }),
      ),
    );

    final sectionLayout = layout.sectionLayouts.single;
    // Two rows at ratio 1 still pack into rows, so the header is not the whole
    // section and the sliver has real content from the first frame.
    expect(sectionLayout.lastIndex, greaterThan(sectionLayout.firstIndex));
    expect(sectionLayout.maxOffset, greaterThan(sectionLayout.minOffset + sectionLayout.headerExtent));

    await pumpSection(tester, layout);
  });

  testWidgets('a stale channel that does not cover the section is ignored', (tester) async {
    late SectionedListLayout<AvesEntry> layout;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (context) {
          // A channel measured for a different view: using it would index past
          // the section.
          layout = buildLayout(context: context, rows: [skeleton, skeleton], ratioResolver: (_) => const [1, 1, 1, 1, 1]);
          return const SizedBox();
        }),
      ),
    );

    expect(layout.sectionLayouts.single.lastIndex, greaterThan(layout.sectionLayouts.single.firstIndex));
    await pumpSection(tester, layout);
  });

  testWidgets('an empty section is its header alone', (tester) async {
    late SectionedListLayout<AvesEntry> layout;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (context) {
          layout = buildLayout(context: context, rows: const [], ratioResolver: (_) => const []);
          return const SizedBox();
        }),
      ),
    );

    final sectionLayout = layout.sectionLayouts.single;
    expect(sectionLayout.firstIndex, sectionLayout.lastIndex);
    // No rows means no row spacing to subtract: the extent is the header's.
    expect(sectionLayout.maxOffset - sectionLayout.minOffset, sectionLayout.headerExtent);

    await pumpSection(tester, layout);
  });
}
