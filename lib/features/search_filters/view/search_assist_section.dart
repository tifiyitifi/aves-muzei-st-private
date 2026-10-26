import 'package:aves/features/search_filters/model/range_assist_filter.dart';
import 'package:aves/features/search_filters/model/search_assist.dart';
import 'package:aves/features/search_filters/view/other_assist_sheet.dart';
import 'package:aves/features/search_filters/view/path_assist_sheet.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/theme/styles.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The "Assist" group of the collection search page.
///
/// Two entry points open sheets, and every condition the user set is listed
/// below them as a removable chip. Nothing is a free-form query string: each
/// chip is a structured condition that the collection turns into filters.
class SearchAssistSection extends StatelessWidget {
  final ValueNotifier<SearchAssist> assist;
  final CollectionSource source;

  /// Called with the whole condition set once the user applies it.
  final ValueChanged<Set<CollectionFilter>> onApply;

  const new({
    super.key,
    required this.assist,
    required this.source,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<SearchAssist>(
      valueListenable: assist,
      builder: (context, value, child) {
        final chips = _conditions(context, value);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.searchAssistSectionTitle, style: AStyles.sectionTitleStyle(context.knownLocale))),
                  if (value.isNotEmpty)
                    TextButton(
                      onPressed: () => assist.value = SearchAssist.empty,
                      child: Text(l10n.searchAssistClear),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    avatar: const Icon(AIcons.path, size: 18),
                    label: Text(l10n.searchAssistPath),
                    selected: value.path != null,
                    onSelected: (_) => _openPath(context, value),
                  ),
                  FilterChip(
                    avatar: const Icon(AIcons.searchAssistOther, size: 18),
                    label: Text(l10n.searchAssistOther),
                    selected: value.hasOther,
                    onSelected: (_) => _openOther(context, value),
                  ),
                ],
              ),
            ),
            if (chips.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final chip in chips)
                      InputChip(
                        label: Text(chip.label),
                        deleteIcon: const Icon(AIcons.clear, size: 18),
                        onDeleted: () => assist.value = value.without(chip.field),
                      ),
                  ],
                ),
              ),
            if (value.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(AIcons.search),
                    label: Text(l10n.searchAssistApply),
                    onPressed: () => onApply(value.toFilters(calendar: settings.avesLocale.calendar)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openPath(BuildContext context, SearchAssist value) async {
    final next = await showPathAssistSheet(context, initial: value);
    if (next != null) assist.value = next;
  }

  Future<void> _openOther(BuildContext context, SearchAssist value) async {
    final next = await showOtherAssistSheet(
      context,
      initial: value,
      extensions: _availableExtensions(),
      calendar: settings.avesLocale.calendar,
    );
    if (next != null) assist.value = next;
  }

  /// Every chip is one removable field; a field that produced several filters
  /// (a dimension has two) stays one chip so removing it cannot leave half a
  /// condition behind.
  List<({AssistField field, String label})> _conditions(BuildContext context, SearchAssist value) {
    final l10n = context.l10n;
    final conditions = <({AssistField field, String label})>[];

    final path = value.path;
    if (path != null) {
      final label = PathFilter(path.path).getLabel(context);
      conditions.add((
        field: AssistField.path,
        label: path.mode == PathAssistMode.include ? l10n.searchAssistPathIncludeLabel(label) : l10n.searchAssistPathExcludeLabel(label),
      ));
    }

    final takenDate = value.takenDate;
    if (takenDate != null) {
      final filter = takenDate.toFilter(AssistRangeField.takenDate);
      if (filter != null) conditions.add((field: AssistField.takenDate, label: filter.getLabel(context)));
    }

    final size = value.size;
    if (size != null) {
      final filter = size.toFilter(AssistRangeField.size);
      if (filter != null) conditions.add((field: AssistField.size, label: filter.getLabel(context)));
    }

    final dimension = value.dimension;
    if (dimension != null && !dimension.isEmpty) {
      final labels = [
        dimension.width.toFilter(AssistRangeField.width)?.getLabel(context),
        dimension.height.toFilter(AssistRangeField.height)?.getLabel(context),
      ].nonNulls;
      if (labels.isNotEmpty) conditions.add((field: AssistField.dimension, label: labels.join(' · ')));
    }

    final contentId = value.contentId;
    if (contentId != null) {
      final filter = contentId.toFilter(AssistRangeField.contentId);
      if (filter != null) conditions.add((field: AssistField.contentId, label: filter.getLabel(context)));
    }

    final recent = value.recent;
    if (recent != null) {
      conditions.add((field: AssistField.recent, label: recent.toFilter().getLabel(context)));
    }

    if (value.extensions.isNotEmpty) {
      final list = (value.extensions.toList()..sort()).map((extension) => extension.toUpperCase()).join(', ');
      conditions.add((field: AssistField.extension, label: l10n.searchAssistExtensions(list)));
    }

    return conditions;
  }

  /// Extensions present in the library, for the format sheet.
  ///
  /// A windowed source holds no entries, so it falls back to the formats the
  /// summary domain knows; the sheet simply offers fewer formats rather than
  /// inventing ones the library does not have.
  List<String> _availableExtensions() {
    final extensions = <String>{};
    for (final entry in source.visibleEntries) {
      final extension = entry.extension;
      if (extension != null && extension.length > 1) extensions.add(extension.substring(1).toLowerCase());
    }
    if (extensions.isEmpty) {
      for (final mime in source.summaries?.mimeTypes ?? const <String>[]) {
        final extension = MimeTypes.extensionFor(mime);
        if (extension != null) extensions.add(extension.substring(1).toLowerCase());
      }
    }
    return extensions.toList()..sort();
  }
}
