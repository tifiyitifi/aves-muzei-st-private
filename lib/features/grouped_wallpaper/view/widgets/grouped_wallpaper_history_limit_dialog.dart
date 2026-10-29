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
Future<int?> showGroupedWallpaperHistoryLimitDialog(BuildContext context, {required int limit}) async {
  final controller = TextEditingController(text: '${GroupedWallpaperHistoryLimit.sanitize(limit)}');
  final theme = Theme.of(context);
  final result = await showDialog<int>(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      return AlertDialog(
        title: Text(l10n.wallpaperGroupHistoryLimit),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: const [_HistoryLimitFormatter()],
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
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              GroupedWallpaperHistoryLimit.sanitize(int.tryParse(controller.text) ?? GroupedWallpaperHistoryLimit.defaultLimit),
            ),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
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
