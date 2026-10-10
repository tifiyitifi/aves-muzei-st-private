import 'package:aves/features/drift_db/migration/legacy_import_progress.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Startup indicator for the one-time legacy database import.
///
/// Renders nothing unless an import is in flight, so it can sit permanently in
/// the home page body. Counts are shown so the user sees real progress instead
/// of a bare spinner.
class LegacyImportIndicator extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LegacyImportProgress?>(
      valueListenable: legacyImportProgress,
      builder: (context, progress, child) {
        if (progress == null) return const SizedBox.shrink();

        final total = progress.totalRows;
        final copied = progress.copiedRows;
        final determinate = total > 0;
        final value = determinate ? (copied / total).clamp(0.0, 1.0) : null;
        final numberFormat = settings.avesLocale.decimalNumberFormat();

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.dbImportTitle,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 240,
                child: LinearProgressIndicator(value: value),
              ),
              const SizedBox(height: 12),
              Text(
                determinate
                    ? context.l10n.dbImportProgress(numberFormat.format(copied), numberFormat.format(total))
                    : context.l10n.dbImportPreparing,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}
