import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for a custom auto-advance interval.
///
/// Returns the chosen value, or null when the user cancelled. The dialog and
/// [WallpaperAdvanceInterval] enforce the same `3 seconds..30 days` bounds, so
/// it can never submit a value the scheduler would have to reject.
Future<WallpaperAdvanceInterval?> showWallpaperIntervalAddDialog(
  BuildContext context, {
  required WallpaperAdvanceInterval current,
}) =>
    showDialog<WallpaperAdvanceInterval>(
      context: context,
      builder: (_) => _AddIntervalDialog(current: current),
    );

class _AddIntervalDialog extends StatefulWidget {
  final WallpaperAdvanceInterval current;

  const new({required this.current});

  @override
  State<_AddIntervalDialog> createState() => _AddIntervalDialogState();
}

class _AddIntervalDialogState extends State<_AddIntervalDialog> {
  late final WallpaperIntervalUnit _initialUnit = widget.current.enabled ? WallpaperIntervalUnit.largestFor(widget.current.seconds) : WallpaperIntervalUnit.hours;
  late final TextEditingController _amount = TextEditingController(
    // Off has no unit to decompose; three hours is the practical starting point.
    text: '${widget.current.enabled ? widget.current.seconds ~/ _initialUnit.secondsPerUnit : 3}',
  );
  late WallpaperIntervalUnit _unit = _initialUnit;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// The typed value in seconds, or null when it is out of range.
  int? get _seconds {
    final amount = int.tryParse(_amount.text);
    if (amount == null || amount <= 0) return null;
    final seconds = amount * _unit.secondsPerUnit;
    if (seconds < WallpaperAdvanceInterval.minSeconds || seconds > WallpaperAdvanceInterval.maxSeconds) return null;
    return seconds;
  }

  void _submit() {
    final seconds = _seconds;
    if (seconds == null) return;
    Navigator.pop(context, WallpaperAdvanceInterval(seconds));
  }

  String _unitLabel(BuildContext context, WallpaperIntervalUnit unit) {
    final l10n = context.l10n;
    return switch (unit) {
      WallpaperIntervalUnit.seconds => l10n.wallpaperIntervalUnitSeconds,
      WallpaperIntervalUnit.minutes => l10n.wallpaperIntervalUnitMinutes,
      WallpaperIntervalUnit.hours => l10n.wallpaperIntervalUnitHours,
      WallpaperIntervalUnit.days => l10n.wallpaperIntervalUnitDays,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final valid = _seconds != null;
    return AlertDialog(
      title: Text(l10n.wallpaperIntervalAddTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.wallpaperIntervalRange,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: l10n.wallpaperIntervalAddAmount,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<WallpaperIntervalUnit>(
                value: _unit,
                onChanged: (unit) {
                  if (unit != null) setState(() => _unit = unit);
                },
                items: [
                  for (final unit in WallpaperIntervalUnit.values)
                    DropdownMenuItem(
                      value: unit,
                      child: Text(_unitLabel(context, unit)),
                    ),
                ],
              ),
            ],
          ),
          if (!valid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.wallpaperIntervalInvalid,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            l10n.wallpaperIntervalTestHint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
        TextButton(onPressed: valid ? _submit : null, child: Text(MaterialLocalizations.of(context).okButtonLabel)),
      ],
    );
  }
}
