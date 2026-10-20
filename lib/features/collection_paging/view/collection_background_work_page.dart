import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/view/collection_import_intro.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The permanent home of the first-run explanation: what the app does while a
/// library is being organized, how long it takes, and how far it has got.
///
/// The dialog says this once; this page is where it stays readable afterwards,
/// which is why the dialog does not offer to show itself again.
class CollectionBackgroundWorkPage extends StatelessWidget {
  static const routeName = '/settings/advanced/background_work';

  /// Route builder, so a caller passes a tearoff instead of a closure.
  static Widget routeBuilder(BuildContext context) => const CollectionBackgroundWorkPage();

  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AvesScaffold(
      appBar: AppBar(
        title: Text(l10n.settingsCollectionBackgroundWorkTile),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _ImportStatusTile(),
            const SizedBox(height: 16),
            Text(l10n.collectionImportIntroBody, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            const CollectionImportEtaTable(),
          ],
        ),
      ),
    );
  }
}

/// Live status: the current import progress, or the size of the collection once
/// it is ready.
class _ImportStatusTile extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedBuilder(
      animation: pagedImportStatus,
      builder: (context, child) {
        if (pagedImportStatus.active) {
          return _StatusRow(
            icon: Icons.sync,
            text: l10n.collectionImportStatusImporting(pagedImportStatus.done, pagedImportStatus.total),
          );
        }
        return FutureBuilder<int>(
          future: localMediaDb.countEntries(),
          builder: (context, snapshot) {
            final count = snapshot.data;
            if (count == null) return const SizedBox();
            return _StatusRow(icon: Icons.check_circle_outline, text: l10n.collectionImportStatusReady(count));
          },
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const new({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
