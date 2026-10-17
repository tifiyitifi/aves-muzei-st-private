import 'package:aves/model/source/section_keys.dart';
import 'package:aves/widgets/common/grid/sections/layout/variable_extent_grid_row.dart';
import 'package:aves/widgets/common/grid/sections/layout/variable_extent_section_layout.dart';
import 'package:aves/widgets/common/grid/sections/layout/variable_extent_sectioned_list_layout.dart';
import 'package:aves/widgets/common/grid/sections/list_layout.dart';
import 'package:aves/widgets/common/grid/sections/mosaic/section_layout_builder.dart';
import 'package:aves/widgets/common/grid/sections/section_layout.dart';
import 'package:aves/widgets/common/grid/sections/section_layout_builder.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

/// The mosaic layout behind the paged engine.
///
/// The shared builder packs `section` itself, which means reading every entry of
/// it: fine while the in-memory list holds them all, impossible for a windowed
/// one, where unloaded rows are skeletons of aspect ratio `1` and every fill
/// would reflow the grid. This builder packs the *ratio channel* the engine
/// measured for the section instead, and renders the same rows over the
/// windowed section, so tiles keep loading as they scroll.
///
/// The packing itself is the shared [MosaicSectionLayoutBuilder.computeMosaicRows],
/// run over ratios: the two paths can never lay a section out differently.
class PagedMosaicSectionLayoutBuilder<T>({
  required super.sections,
  required super.showHeaders,
  required super.getHeaderExtent,
  required super.buildHeader,
  required super.scrollableWidth,
  required super.tileLayout,
  required super.columnCount,
  required super.spacing,
  required super.horizontalPadding,
  required super.tileWidth,
  required super.tileHeight,
  required super.tileBuilder,
  required Duration tileAnimationDelay,
  required final List<double>? Function(SectionKey sectionKey) ratioResolver,
}) extends SectionLayoutBuilder<T> {
  int _currentIndex = 0;
  double _currentOffset = 0;
  late double Function(int itemCount) rowAvailableWidth;
  late double rowHeightMax;

  this : super(tileAnimationDelay: Duration(milliseconds: (tileAnimationDelay.inMilliseconds / columnCount).ceil())) {
    final rowWidth = scrollableWidth - horizontalPadding * 2;
    rowAvailableWidth = (itemCount) => rowWidth - (itemCount - 1) * spacing;
    rowHeightMax = tileWidth * MosaicSectionLayoutBuilder.heightMaxFactor;
  }

  @override
  SectionedListLayout<T> updateLayouts(BuildContext context) {
    final sectionLayouts = sections.keys
        .map(
          (sectionKey) => buildSectionLayout(
            headerExtent: showHeaders ? getHeaderExtent(context, sectionKey) : 0.0,
            sectionKey: sectionKey,
            section: sections[sectionKey]!,
            animate: animate,
          ),
        )
        .toList();

    return VariableExtentSectionedListLayout<T>(
      sections: sections,
      showHeaders: showHeaders,
      spacing: spacing,
      horizontalPadding: horizontalPadding,
      sectionLayouts: sectionLayouts,
    );
  }

  @override
  SectionLayout buildSectionLayout({
    required double headerExtent,
    required SectionKey sectionKey,
    required List<T> section,
    required bool animate,
  }) {
    final ratios = ratioResolver(sectionKey);
    // Until the channel lands the section is its header alone: packing the
    // skeletons would place every tile at ratio `1` and reflow on the next fill.
    // The engine notifies when the ratios arrive, and the section is rebuilt.
    final rows = ratios == null
        ? const <VariableExtentRowLayout>[]
        : MosaicSectionLayoutBuilder.computeMosaicRows<double>(
            section: ratios,
            availableWidthFor: rowAvailableWidth,
            heightMax: rowHeightMax,
            targetExtent: tileWidth,
            spacing: spacing,
            bottom: bottom,
            coverRatioResolver: (ratio) => ratio.clamp(MosaicSectionLayoutBuilder.minThumbnailAspectRatio, MosaicSectionLayoutBuilder.maxThumbnailAspectRatio),
          );
    final rowCount = rows.length;
    final sectionChildCount = 1 + rowCount;

    final sectionFirstIndex = _currentIndex;
    _currentIndex += sectionChildCount;
    final sectionLastIndex = _currentIndex - 1;

    final sectionMinOffset = _currentOffset;
    _currentOffset += headerExtent + rows.map((v) => v.height).sum - spacing;
    final sectionMaxOffset = _currentOffset;

    return VariableExtentSectionLayout(
      sectionKey: sectionKey,
      firstIndex: sectionFirstIndex,
      lastIndex: sectionLastIndex,
      minOffset: sectionMinOffset,
      maxOffset: sectionMaxOffset,
      headerExtent: headerExtent,
      rows: rows,
      spacing: spacing,
      builder: (context, listIndex) {
        final textDirection = Directionality.of(context);
        final sectionChildIndex = listIndex - sectionFirstIndex;
        final isHeader = sectionChildIndex == 0;
        final row = isHeader ? rows.first : rows[sectionChildIndex - 1];
        final sectionGridIndex = isHeader ? sectionFirstIndex * columnCount : (sectionChildIndex + 1) * columnCount + row.firstIndex;
        return buildSectionWidget(
          context: context,
          section: section,
          sectionGridIndex: sectionGridIndex,
          sectionChildIndex: sectionChildIndex,
          itemIndexRange: () => isHeader ? const (0, 0) : (row.firstIndex, row.lastIndex + 1),
          sectionKey: sectionKey,
          headerExtent: headerExtent,
          itemSizes: row.itemWidths.map((v) => Size(v, row.height)).toList(),
          animate: animate,
          buildGridRow: (children) {
            return isHeader
                ? const SizedBox()
                : VariableExtentGridRow(
                    rowLayout: row,
                    spacing: spacing,
                    textDirection: textDirection,
                    children: children,
                  );
          },
        );
      },
    );
  }
}
