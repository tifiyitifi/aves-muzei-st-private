import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_limit.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for the usage history limit.
///
/// Returns the chosen value, or null when the user cancelled. `0` is valid: it
/// turns recording off without deleting what was already recorded. The field is
/// clamped while typing, so the dialog can never submit a value the store would
/// reject.
Future<int?> showGroupedWallpaperHistoryLimitDialog(BuildContext context, {required int limit}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _HistoryLimitDialog(limit: limit),
  );
}

/// A stateful dialog so the field's controller lives exactly as long as the
/// route does.
///
/// The previous version disposed the controller as soon as `showDialog` returned
/// and the dialog was still animating out, so the rebuilding `TextField` used a
/// disposed controller, which threw and turned the page into an error screen.
class _HistoryLimitDialog extends StatefulWidget {
  final int limit;

  const new({required this.limit});

  @override
  State<_HistoryLimitDialog> createState() => _HistoryLimitDialogState();
}

class _HistoryLimitDialogState extends State<_HistoryLimitDialog> {
  late final TextEditingController _controller = TextEditingController(text: '${GroupedWallpaperHistoryLimit.sanitize(widget.limit)}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(
        context,
        GroupedWallpaperHistoryLimit.sanitize(int.tryParse(_controller.text) ?? GroupedWallpaperHistoryLimit.defaultLimit),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.wallpaperGroupHistoryLimit),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: const [_HistoryLimitFormatter()],
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              hintText: '0–${GroupedWallpaperHistoryLimit.maxLimit}',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.wallpaperGroupHistoryLimitHint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
        TextButton(onPressed: _submit, child: Text(MaterialLocalizations.of(context).okButtonLabel)),
      ],
    );
  }
}

/// Keeps the field to digits and to the supported range as the user types.
///
/// Clamping on the way in (instead of on submit) is what the plan asks for: the
/// number the user sees is the number that will be stored.
class _HistoryLimitFormatter extends TextInputFormatter {
  const new();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp('[^0-9]'), '');
    final text = digits.isEmpty ? '' : '${GroupedWallpaperHistoryLimit.sanitize(int.tryParse(digits) ?? 0)}';
    // The cursor stays at the end: a clamp can shorten the text, and keeping the
    // old offset would put it past the last digit.
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
