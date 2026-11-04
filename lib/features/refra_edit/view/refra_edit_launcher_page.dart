import 'package:aves/features/refra_edit/view/refra_edit_flow.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Runs the copy-first edit flow for an entry the app was launched with.
///
/// An `edit` launch intent only names a photo; the flow still copies it before any editor opens,
/// then this page closes itself so the user lands back where they came from. As an external edit
/// launch this page is the app's root route, which cannot be popped: closing the app is what hands
/// focus back to the caller.
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
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        // Root route: leave the app instead of stranding the user on the empty spinner.
        await SystemNavigator.pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
