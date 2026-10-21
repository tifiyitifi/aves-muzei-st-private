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
  required final double Function(T item) coverRatioResolver,
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
    final ratios = _packingRatios(sectionKey, section);
    // A section with no rows is its header alone: there is no row to index, and
    // subtracting a row spacing would give it a negative extent.
    final rows = ratios.isEmpty
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
    _currentOffset += headerExtent + (rowCount > 0 ? rows.map((v) => v.height).sum - spacing : 0.0);
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
        // The header has no row behind it. Reading `rows.first` here crashed the
        // whole sliver as soon as a section had no packing yet, which is exactly
        // the first frame of every switch to the mosaic layout.
        final row = sectionChildIndex < 1 || rows.isEmpty ? null : rows[sectionChildIndex - 1];
        final sectionGridIndex = row == null ? sectionFirstIndex * columnCount : (sectionChildIndex + 1) * columnCount + row.firstIndex;
        return buildSectionWidget(
          context: context,
          section: section,
          sectionGridIndex: sectionGridIndex,
          sectionChildIndex: sectionChildIndex,
          itemIndexRange: () => row == null ? const (0, 0) : (row.firstIndex, row.lastIndex + 1),
          sectionKey: sectionKey,
          headerExtent: headerExtent,
          itemSizes: row == null ? const <Size>[] : row.itemWidths.map((v) => Size(v, row.height)).toList(),
          animate: animate,
          buildGridRow: (children) {
            return row == null
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

  /// Ratios to pack [section] with, in its row order.
  ///
  /// A measured channel is used only when it covers exactly the section's rows:
  /// one left over from a different view would index past the section. Until it
  /// lands, or when it does not match, the section packs itself (unloaded rows
  /// have ratio 1) instead of rendering as an empty band — the shared packing
  /// cannot misplace an index, and a filled window replaces it once measured.
  List<double> _packingRatios(SectionKey sectionKey, List<T> section) {
    final measured = ratioResolver(sectionKey);
    if (measured != null && measured.length == section.length) return measured;
    return [for (final item in section) coverRatioResolver(item)];
  }
}
