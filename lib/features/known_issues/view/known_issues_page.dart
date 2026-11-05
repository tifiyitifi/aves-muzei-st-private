import 'package:aves/features/known_issues/view/known_issues_section.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Scrollable list of every accepted limitation.
///
/// Reached from Advanced so the batch engine's v1 scope (filters/geometry only,
/// no RAW) is documented next to the engine selector, not buried in About. The
/// entries come from [knownIssues], the same source the About section renders.
class KnownIssuesPage extends StatelessWidget {
  static const routeName = '/settings/known_issues';

  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final issues = knownIssues(context);
    return AvesScaffold(
      appBar: AppBar(title: Text(context.l10n.aboutKnownIssuesSectionTitle)),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: issues.length,
          itemBuilder: (context, index) => KnownIssuesSection.knownIssueRow(context, index, issues[index]),
        ),
      ),
    );
  }
}
