import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The strip under a timeline that is a preview, pointing at the whole album
/// list and offering the rows the preview stopped short of.
///
/// It states how many rows the timeline **shows**, not how many the window read:
/// a hidden album is read but not rendered, and a count that includes it would
/// claim rows the user cannot see. The read budget stays on the raw row count in
/// `BrowseLibrary.atLimit`.
class BrowseTimelinePreview extends StatelessWidget {
  /// Rows in the displayed order, i.e. what the grid renders.
  final int count;

  /// Whether the last page failed: the action retries instead of loading more.
  final bool failed;

  /// Asks for the rows past the preview limit.
  final VoidCallback onContinue;

  /// Retries the page that failed.
  final VoidCallback onRetry;

  const new({
    super.key,
    required this.count,
    required this.failed,
    required this.onContinue,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 6),
        child: Row(
          children: [
            Icon(AIcons.image, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.browseOnlyTimelinePreview(count),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              style: TextButton.styleFrom(
                // The strip is one line high: a default-sized button would
                // overflow it.
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                foregroundColor: color,
              ),
              onPressed: failed ? onRetry : onContinue,
              child: Text(context.l10n.browseOnlyTimelineContinue),
            ),
          ],
        ),
      ),
    );
  }
}
