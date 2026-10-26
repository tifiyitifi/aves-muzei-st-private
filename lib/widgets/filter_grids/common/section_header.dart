import 'package:aves/widgets/common/grid/header.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:material_ui/material_ui.dart';

class const FilterChipSectionHeader<T>({
  super.key,
  required final ChipSectionKey sectionKey,
  required final bool selectable,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SectionHeader<T>(
      sectionKey: sectionKey,
      leading: sectionKey.leading,
      title: sectionKey.title,
      titleStyle: sectionKey.titleStyle,
      // A read-only section (e.g. the active conditions summary) opts out of
      // header selection and may show a state label on the right.
      selectable: selectable && sectionKey.selectable,
      trailing: sectionKey.buildTrailing(context),
    );
  }

  static double getPreferredHeight(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return textScaler.scale(SectionHeader.leadingSize.height) + SectionHeader.padding.vertical + SectionHeader.margin.vertical;
  }
}
