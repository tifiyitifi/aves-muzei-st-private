import 'package:aves/widgets/about/title.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Documents the trade-offs of the paged (non-full-load) engine on the About
/// page.
///
/// The content lives in the fork so upstream's About page only gains one more
/// section. Only limitations the project accepts for good belong here: an entry
/// is removed once its limitation is lifted, so anything already planned for
/// implementation (e.g. burst/RAW stacking, the calendar and mosaic layouts)
/// stays out of the list, and the entry explaining the "unsupported" notice
/// names no specific view for that reason.
class KnownIssuesSection extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          AboutSectionTitle(text: context.l10n.aboutKnownIssuesSectionTitle),
          const SizedBox(height: 8),
          buildBody(context),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// The numbered entries, shared by the mobile list and the TV page.
  static Widget buildBody(BuildContext context) {
    final l10n = context.l10n;
    final issues = [
      l10n.aboutKnownIssues1,
      l10n.aboutKnownIssues2,
      l10n.aboutKnownIssues3,
      l10n.aboutKnownIssues4,
    ];
    return Column(
      crossAxisAlignment: .start,
      children: [
        for (var index = 0; index < issues.length; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: .start,
              children: [
                // The number is a widget of its own rather than concatenated
                // display text, so it keeps its own side under RTL.
                Text('${index + 1}.'),
                const SizedBox(width: 8),
                Expanded(child: Text(issues[index])),
              ],
            ),
          ),
      ],
    );
  }
}
