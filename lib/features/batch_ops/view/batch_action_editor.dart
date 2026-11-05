import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/view/batch_tool_catalog.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Filter names exposed by the built-in editor (`ImageFilterTypes`).
const List<String> batchFilterNames = [
  'Lite',
  'Playa',
  'Honey',
  'Isla',
  'Desert',
  'Clay',
  'Palma',
  'Blush',
  'Alpaca',
  'Modena',
  'West',
  'Metro',
  'Reel',
  'Bazaar',
  'Ollie',
  'Onyx',
  'Eiffel',
  'Vogue',
  'Vista',
  'Astro',
  'Negative',
];

/// One variable filter with the range the native editor declares.
class BatchAdjustmentSpec {
  final String name;
  final double min;
  final double max;
  final double defaultValue;

  const new(this.name, this.min, this.max, this.defaultValue);
}

const List<BatchAdjustmentSpec> batchAdjustmentSpecs = [
  BatchAdjustmentSpec('Brightness', -1, 1, 0),
  BatchAdjustmentSpec('Contrast', 0, 2, 1),
  BatchAdjustmentSpec('Saturation', 0, 2, 1),
  BatchAdjustmentSpec('Warmth', -1, 1, 0),
  BatchAdjustmentSpec('Tint', -1, 1, 0),
  BatchAdjustmentSpec('Hue', -1, 1, 0),
  BatchAdjustmentSpec('Shadows', -1, 1, 0),
  BatchAdjustmentSpec('Highlights', -1, 1, 0),
  BatchAdjustmentSpec('Vignette', 0, 1, 0),
  BatchAdjustmentSpec('Sharpen', 3, 9, 5),
];

Future<BatchAction?> showBatchActionEditor(BuildContext context, BatchAction action) {
  return showDialog<BatchAction>(
    context: context,
    builder: (context) => _BatchActionEditorDialog(action: action),
  );
}

class _BatchActionEditorDialog extends StatefulWidget {
  final BatchAction action;

  const new({required this.action});

  @override
  State<_BatchActionEditorDialog> createState() => _BatchActionEditorDialogState();
}

class _BatchActionEditorDialogState extends State<_BatchActionEditorDialog> {
  late BatchAction _action = widget.action;
  late final TextEditingController _footerText = TextEditingController(text: _action.settings['text'] as String? ?? '');
  late final TextEditingController _resizeLongEdge = TextEditingController(text: '${(_action.settings['maxLongEdge'] as num?)?.toInt() ?? 0}');

  @override
  void dispose() {
    _footerText.dispose();
    _resizeLongEdge.dispose();
    super.dispose();
  }

  void _update(Map<String, Object?> settings) {
    setState(() => _action = _action.copyWith(settings: settings));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final info = batchToolInfo(_action.kind);
    return AlertDialog(
      title: Text(info.title(context)),
      content: SingleChildScrollView(child: _buildBody(context)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _action),
          child: Text(l10n.applyButtonLabel),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;
    switch (_action.kind) {
      case BatchToolKind.filter:
        return _buildFilter(l10n);
      case BatchToolKind.adjust:
        return _buildAdjust(l10n);
      case BatchToolKind.rotate:
        return _buildRotate(l10n);
      case BatchToolKind.flip:
        return _buildFlip(l10n);
      case BatchToolKind.crop:
        return _buildCrop(l10n);
      case BatchToolKind.resize:
        return _buildResize(l10n);
      case BatchToolKind.convert:
        return _buildConvert(l10n);
      case BatchToolKind.footer:
        return _buildFooter(l10n);
      case BatchToolKind.refreshTime:
        return const SizedBox.shrink();
      case BatchToolKind.recipe:
        return Text(l10n.batchEditorRecipeReadOnly);
    }
  }

  Widget _buildFilter(AppLocalizations l10n) {
    final name = _action.settings['name'] as String? ?? batchFilterNames.first;
    final intensity = (_action.settings['intensity'] as num?)?.toDouble() ?? 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          isExpanded: true,
          value: batchFilterNames.contains(name) ? name : batchFilterNames.first,
          items: [for (final value in batchFilterNames) DropdownMenuItem(value: value, child: Text(value))],
          onChanged: (value) {
            if (value == null) return;
            _update({..._action.settings, 'name': value});
          },
        ),
        const SizedBox(height: 12),
        Text(l10n.batchEditorPercent(l10n.batchEditorFilterIntensity, (intensity * 100).round())),
        Slider(
          value: intensity.clamp(0, 1),
          min: 0,
          max: 1,
          divisions: 20,
          label: '${(intensity * 100).round()}%',
          onChanged: (value) => _update({..._action.settings, 'intensity': value}),
        ),
      ],
    );
  }

  Widget _buildAdjust(AppLocalizations l10n) {
    final name = _action.settings['name'] as String? ?? batchAdjustmentSpecs.first.name;
    final spec = batchAdjustmentSpecs.firstWhere((s) => s.name == name, orElse: () => batchAdjustmentSpecs.first);
    final value = (_action.settings['value'] as num?)?.toDouble() ?? spec.defaultValue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          isExpanded: true,
          value: spec.name,
          items: [for (final item in batchAdjustmentSpecs) DropdownMenuItem(value: item.name, child: Text(item.name))],
          onChanged: (value) {
            if (value == null) return;
            final next = batchAdjustmentSpecs.firstWhere((s) => s.name == value);
            _update({'name': value, 'value': next.defaultValue});
          },
        ),
        const SizedBox(height: 12),
        Text(l10n.batchEditorNumber(l10n.batchEditorAdjustValue, value.toStringAsFixed(2))),
        Slider(
          value: value.clamp(spec.min, spec.max),
          min: spec.min,
          max: spec.max,
          divisions: 20,
          label: value.toStringAsFixed(2),
          onChanged: (value) => _update({..._action.settings, 'value': value}),
        ),
      ],
    );
  }

  Widget _buildRotate(AppLocalizations l10n) {
    final angle = (_action.settings['angle'] as num?)?.toDouble() ?? 90;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.batchEditorRotateAngle),
        const SizedBox(height: 12),
        SegmentedButton<double>(
          segments: [
            ButtonSegment(value: 90, label: Text(l10n.batchEditorDegrees(90))),
            ButtonSegment(value: 180, label: Text(l10n.batchEditorDegrees(180))),
            ButtonSegment(value: 270, label: Text(l10n.batchEditorDegrees(270))),
          ],
          selected: {angle == 180 ? 180 : (angle == 270 ? 270 : 90)},
          onSelectionChanged: (values) => _update({..._action.settings, 'angle': values.first}),
        ),
      ],
    );
  }

  Widget _buildFlip(AppLocalizations l10n) {
    final horizontal = _action.settings['horizontal'] != false;
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment(value: true, label: Text(l10n.batchEditorFlipHorizontal)),
        ButtonSegment(value: false, label: Text(l10n.batchEditorFlipVertical)),
      ],
      selected: {horizontal},
      onSelectionChanged: (values) => _update({..._action.settings, 'horizontal': values.first}),
    );
  }

  Widget _buildCrop(AppLocalizations l10n) {
    final raw = (_action.settings['rect'] as List?)?.map((value) => (value as num).toDouble()).toList();
    final rect = raw != null && raw.length == 4 ? raw : <double>[0, 0, 1, 1];
    final left = rect[0].clamp(0.0, 0.45);
    final top = rect[1].clamp(0.0, 0.45);
    final right = (1 - rect[2]).clamp(0.0, 0.45);
    final bottom = (1 - rect[3]).clamp(0.0, 0.45);

    void update(List<double> next) => _update({..._action.settings, 'rect': next});

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _marginSlider(l10n.batchEditorCropLeft, left, (value) => update([value, rect[1], rect[2], rect[3]])),
        _marginSlider(l10n.batchEditorCropTop, top, (value) => update([rect[0], value, rect[2], rect[3]])),
        _marginSlider(l10n.batchEditorCropRight, right, (value) => update([rect[0], rect[1], 1 - value, rect[3]])),
        _marginSlider(l10n.batchEditorCropBottom, bottom, (value) => update([rect[0], rect[1], rect[2], 1 - value])),
      ],
    );
  }

  Widget _marginSlider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.batchEditorPercent(label, (value * 100).round())),
        Slider(
          value: value,
          min: 0,
          max: 0.45,
          divisions: 18,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildResize(AppLocalizations l10n) {
    final percent = (_action.settings['percent'] as num?)?.toInt() ?? 100;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _resizeLongEdge,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: l10n.batchEditorResizeLongEdge),
          onChanged: (value) {
            final next = int.tryParse(value) ?? 0;
            _update({..._action.settings, 'maxLongEdge': next});
          },
        ),
        const SizedBox(height: 12),
        Text(l10n.batchEditorPercent(l10n.batchEditorResizePercent, percent)),
        Slider(
          value: percent.clamp(10, 100).toDouble(),
          min: 10,
          max: 100,
          divisions: 18,
          onChanged: (value) => _update({..._action.settings, 'percent': value.round()}),
        ),
      ],
    );
  }

  Widget _buildConvert(AppLocalizations l10n) {
    const formats = ['keep', 'jpeg', 'png', 'webp'];
    final format = _action.settings['format'] as String? ?? 'keep';
    final quality = (_action.settings['quality'] as num?)?.toInt() ?? 100;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          isExpanded: true,
          value: formats.contains(format) ? format : 'keep',
          items: [
            DropdownMenuItem(value: 'keep', child: Text(l10n.batchEditorFormatKeep)),
            DropdownMenuItem(value: 'jpeg', child: Text(l10n.batchEditorFormatJpeg)),
            DropdownMenuItem(value: 'png', child: Text(l10n.batchEditorFormatPng)),
            DropdownMenuItem(value: 'webp', child: Text(l10n.batchEditorFormatWebp)),
          ],
          onChanged: (value) {
            if (value == null) return;
            _update({..._action.settings, 'format': value});
          },
        ),
        const SizedBox(height: 12),
        Text(l10n.batchEditorNumber(l10n.batchEditorConvertQuality, '$quality')),
        Slider(
          value: quality.clamp(50, 100).toDouble(),
          min: 50,
          max: 100,
          divisions: 10,
          onChanged: (value) => _update({..._action.settings, 'quality': value.round()}),
        ),
      ],
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    final bandHeight = (_action.settings['bandHeightPercent'] as num?)?.toInt() ?? 8;
    final textSize = (_action.settings['textSizePercent'] as num?)?.toInt() ?? 55;
    final atTop = _action.settings['atTop'] == true;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _footerText,
          decoration: InputDecoration(
            labelText: l10n.batchEditorFooterText,
            hintText: l10n.batchEditorFooterTextHint,
          ),
          onChanged: (value) {
            final settings = {..._action.settings};
            if (value.isEmpty) {
              settings.remove('text');
            } else {
              settings['text'] = value;
            }
            _update(settings);
          },
        ),
        const SizedBox(height: 12),
        Text(l10n.batchEditorPercent(l10n.batchEditorFooterBandHeight, bandHeight)),
        Slider(
          value: bandHeight.clamp(2, 20).toDouble(),
          min: 2,
          max: 20,
          divisions: 18,
          onChanged: (value) => _update({..._action.settings, 'bandHeightPercent': value.round()}),
        ),
        Text(l10n.batchEditorPercent(l10n.batchEditorFooterTextSize, textSize)),
        Slider(
          value: textSize.clamp(20, 90).toDouble(),
          min: 20,
          max: 90,
          divisions: 14,
          onChanged: (value) => _update({..._action.settings, 'textSizePercent': value.round()}),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.batchEditorFooterAtTop),
          value: atTop,
          onChanged: (value) => _update({..._action.settings, 'atTop': value}),
        ),
      ],
    );
  }
}
