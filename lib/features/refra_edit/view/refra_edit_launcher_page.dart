import 'package:aves/features/refra_edit/view/refra_edit_flow.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:flutter/material.dart';

/// Runs the copy-first edit flow for an entry the app was launched with.
///
/// An `edit` launch intent only names a photo; the flow still copies it before any editor opens,
/// then this page closes itself so the user lands back where they came from.
class RefraEditLauncherPage extends StatefulWidget {
  static const routeName = '/refra_edit_launcher';

  final AvesEntry entry;

  const new({
    super.key,
    required this.entry,
  });

  @override
  State<RefraEditLauncherPage> createState() => _RefraEditLauncherPageState();
}

class _RefraEditLauncherPageState extends State<RefraEditLauncherPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await startRefraEdit(context, widget.entry);
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
