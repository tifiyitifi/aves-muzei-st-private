import 'dart:async';

import 'package:aves/features/refra_edit/model/refra_edit_session.dart';
import 'package:aves/features/refra_edit/services/refra_edit_service.dart';
import 'package:aves/features/refra_edit/view/refra_edit_intro_dialog.dart';
import 'package:aves/features/refra_edit/view/refra_edit_sessions_page.dart';
import 'package:aves/widgets/common/basic/divider.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/material.dart';

/// Fork settings for the copy-first editor.
///
/// It explains the staging model, summarises what currently sits in the staging directory, and
/// links to the per-session page where copies can be moved back to their source directory.
class RefraEditSettingsPage extends StatefulWidget {
  static const routeName = '/settings/refra_edit';

  const new({super.key});

  @override
  State<RefraEditSettingsPage> createState() => _RefraEditSettingsPageState();
}

class _RefraEditSettingsPageState extends State<RefraEditSettingsPage> {
  List<RefraEditSession>? _sessions;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final store = await refraEditService.store();
    final sessions = await store.getSessions();
    if (!mounted) return;
    setState(() => _sessions = sessions);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sessions = _sessions;
    final active = sessions?.where((s) => s.status == RefraEditSessionStatus.active).length ?? 0;

    return AvesScaffold(
      appBar: AppBar(title: Text(l10n.refraEditSettingsTitle)),
      body: sessions == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(
                      l10n.refraEditSettingsExplanation,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      l10n.refraEditStagingSummary(active),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const ThinDivider(),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: Text(l10n.refraEditSessionsTitle),
                    subtitle: Text(l10n.refraEditSessionsSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RefraEditSessionsPage()),
                      );
                      await _load();
                    },
                  ),
                  const ThinDivider(),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(l10n.refraEditShowIntro),
                    subtitle: Text(l10n.refraEditShowIntroSubtitle),
                    onTap: () => showRefraEditIntroDialog(context),
                  ),
                ],
              ),
            ),
    );
  }
}
