import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_interval_parts.dart';
import 'package:aves/features/wallpaper_auto_advance/view/wallpaper_interval_label.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Width below which the editor opens as a bottom sheet instead of a dialog.
///
/// Mirrors the M3 compact breakpoint used by the other fork-owned form sheets:
/// a phone gets a sheet that hugs the keyboard, a tablet/desktop gets a card.
const double _kIntervalSheetBreakpoint = 600;

/// Asks for a custom auto-advance interval with four number boxes.
///
/// Returns the chosen value, or null when the user cancelled. The editor and
/// [WallpaperAdvanceInterval] enforce the same `3 seconds..30 days` bounds, so
/// it can never submit a value the scheduler would have to reject.
///
/// Performance: the form is built ONCE and cached in the shell, and the shell
/// never reads `MediaQuery.viewInsetsOf` itself. Only the leaf
/// [_KeyboardInsetPadder] subscribes to the keyboard inset, so IME animation
/// frames just move padding instead of rebuilding the four fields — the same
/// pattern that fixed the tall-keyboard stalls in the IRIS rule editor. On
/// mobile the fields also do not autofocus: letting the IME start while the
/// sheet is still animating in is what makes the open gesture stutter.
Future<WallpaperAdvanceInterval?> showWallpaperIntervalAddSheet(
  BuildContext context, {
  required WallpaperAdvanceInterval current,
}) {
  // An existing value is decomposed so the editor continues from it; Off has no
  // unit to decompose, so ten minutes is the practical starting point.
  final initial = current.enabled ? WallpaperIntervalParts.fromSeconds(current.seconds) : WallpaperIntervalParts.defaultTenMinutes;
  final sheet = MediaQuery.sizeOf(context).width < _kIntervalSheetBreakpoint;
  if (sheet) {
    return showModalBottomSheet<WallpaperAdvanceInterval>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _IntervalAddSheet(initial: initial, autofocus: false),
    );
  }
  return showDialog<WallpaperAdvanceInterval>(
    context: context,
    builder: (_) => _IntervalAddSheet(initial: initial, autofocus: true),
  );
}

class _IntervalAddSheet extends StatefulWidget {
  final WallpaperIntervalParts initial;

  /// Desktop only: mobile opens the IME after the entrance animation instead.
  final bool autofocus;

  const new({
    required this.initial,
    required this.autofocus,
  });

  @override
  State<_IntervalAddSheet> createState() => _IntervalAddSheetState();
}

class _IntervalAddSheetState extends State<_IntervalAddSheet> {
  late final TextEditingController _days = TextEditingController(text: _initialText(widget.initial.days));
  late final TextEditingController _hours = TextEditingController(text: _initialText(widget.initial.hours));
  late final TextEditingController _minutes = TextEditingController(text: _initialText(widget.initial.minutes));
  late final TextEditingController _seconds = TextEditingController(text: _initialText(widget.initial.seconds));

  /// The summed value, read by the preview and the confirm button only. Keeping
  /// it out of `setState` means typing never rebuilds the fields.
  late final ValueNotifier<int> _total = ValueNotifier(widget.initial.totalSeconds);

  /// Built on the first frame, then reused: keyboard frames must not recreate it.
  Widget? _form;

  /// Zero is shown as an empty box with a `0` hint, so typing does not append to
  /// a leading zero.
  static String _initialText(int value) => value == 0 ? '' : '$value';

  @override
  void dispose() {
    _days.dispose();
    _hours.dispose();
    _minutes.dispose();
    _seconds.dispose();
    _total.dispose();
    super.dispose();
  }

  WallpaperIntervalParts get _parts => WallpaperIntervalParts(
        days: int.tryParse(_days.text) ?? 0,
        hours: int.tryParse(_hours.text) ?? 0,
        minutes: int.tryParse(_minutes.text) ?? 0,
        seconds: int.tryParse(_seconds.text) ?? 0,
      );

  void _refresh() => _total.value = _parts.totalSeconds;

  void _submit() {
    if (!_parts.isValid) return;
    Navigator.pop(context, WallpaperAdvanceInterval(_parts.totalSeconds));
  }

  void _cancel() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final form = _form ??= _buildForm(context);
    final height = MediaQuery.sizeOf(context).height;
    // `MediaQuery.sizeOf` ignores the keyboard inset, so this last read cannot
    // turn the shell into a per-keyboard-frame rebuild.
    final content = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height * 0.92, maxWidth: dialog ? 420 : double.infinity),
      child: form,
    );
    return _KeyboardInsetPadder(
      child: dialog ? Dialog(insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24), child: content) : content,
    );
  }

  bool get dialog => MediaQuery.sizeOf(context).width >= _kIntervalSheetBreakpoint;

  Widget _buildForm(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text(l10n.wallpaperIntervalAddTitle, style: theme.textTheme.titleLarge)),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close),
                onPressed: _cancel,
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.wallpaperIntervalRange, style: hintStyle),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field(context, _days, l10n.wallpaperIntervalUnitDays, TextInputAction.next),
                    const SizedBox(width: 8),
                    _field(context, _hours, l10n.wallpaperIntervalUnitHours, TextInputAction.next),
                    const SizedBox(width: 8),
                    _field(context, _minutes, l10n.wallpaperIntervalUnitMinutes, TextInputAction.next),
                    const SizedBox(width: 8),
                    _field(context, _seconds, l10n.wallpaperIntervalUnitSeconds, TextInputAction.done),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l10n.wallpaperIntervalAddEachMax, style: hintStyle),
                const SizedBox(height: 12),
                ValueListenableBuilder<int>(
                  valueListenable: _total,
                  builder: (context, total, _) {
                    final valid = _isValidTotal(total);
                    // Same phrasing as the picker, so the preview cannot disagree
                    // with the option that will be added.
                    return Text(
                      valid ? wallpaperAdvanceIntervalLabel(context, WallpaperAdvanceInterval(total)) : l10n.wallpaperIntervalInvalid,
                      style: theme.textTheme.bodyMedium?.copyWith(color: valid ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.error),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(l10n.wallpaperIntervalTestHint, style: hintStyle),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
          child: ValueListenableBuilder<int>(
            valueListenable: _total,
            builder: (context, total, _) => Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _cancel,
                  child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isValidTotal(total) ? _submit : null,
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static bool _isValidTotal(int total) =>
      total >= WallpaperAdvanceInterval.minSeconds && total <= WallpaperAdvanceInterval.maxSeconds;

  Widget _field(BuildContext context, TextEditingController controller, String label, TextInputAction action) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A narrow phone gives each box ~60 dp, which 「Minutes」 can outgrow;
          // scaling down keeps the column headers instead of ellipsizing them.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textInputAction: action,
            textAlign: TextAlign.center,
            autofocus: widget.autofocus && _autofocusController == controller,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              const _MaxFieldFormatter(WallpaperIntervalParts.maxFieldValue),
            ],
            onChanged: (_) => _refresh(),
            onSubmitted: action == TextInputAction.done ? (_) => _submit() : null,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Desktop autofocus target: the first non-zero box, so the user can edit the
  /// value they came in with instead of retyping all four.
  TextEditingController get _autofocusController {
    for (final controller in [_days, _hours, _minutes, _seconds]) {
      if (controller.text.isNotEmpty) return controller;
    }
    return _minutes;
  }
}

/// Keeps a box at or below [max] without the value jumping mid-edit.
///
/// Rejects the whole edit rather than truncating it: turning a pasted `5000`
/// into `500` would silently create a different interval.
class _MaxFieldFormatter extends TextInputFormatter {
  final int max;

  const new(this.max);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final parsed = int.tryParse(newValue.text);
    if (parsed != null && parsed > max) return oldValue;
    return newValue;
  }
}

/// The ONE widget allowed to consume the software-keyboard inset.
///
/// Reading `MediaQuery.viewInsetsOf` rebuilds the reader on EVERY keyboard
/// animation frame. Isolating that read in this leaf keeps the cached form out
/// of those rebuilds: keyboard frames only repad an already-built child. Inside
/// a [Dialog] it is inert, because the dialog already removes view insets.
class _KeyboardInsetPadder extends StatelessWidget {
  final Widget child;

  const new({required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}
