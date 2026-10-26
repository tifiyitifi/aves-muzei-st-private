import 'dart:async';

import 'package:aves/features/search_filters/model/search_assist.dart';
import 'package:aves/features/search_filters/model/time_to_now.dart';
import 'package:aves/features/search_filters/services/assist_counter.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/utils/file_utils.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the sheet holding every condition except the path.
///
/// Returns the updated assist, or null when the sheet was dismissed.
Future<SearchAssist?> showOtherAssistSheet(
  BuildContext context, {
  required SearchAssist initial,
  required List<String> extensions,
  required ACalendar calendar,
}) {
  return showModalBottomSheet<SearchAssist>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _OtherAssistSheet(initial: initial, extensions: extensions, calendar: calendar),
  );
}

enum _SizeUnit {
  kb(1 << 10, 'KB'),
  mb(1 << 20, 'MB'),
  gb(1 << 30, 'GB');

  final int bytes;
  final String label;

  new(this.bytes, this.label);
}

class _OtherAssistSheet extends StatefulWidget {
  final SearchAssist initial;
  final List<String> extensions;
  final ACalendar calendar;

  const new({required this.initial, required this.extensions, required this.calendar});

  @override
  State<_OtherAssistSheet> createState() => _OtherAssistSheetState();
}

class _OtherAssistSheetState extends State<_OtherAssistSheet> {
  late AssistIntRange? _date = widget.initial.takenDate;
  late AssistRecent? _recent = widget.initial.recent;
  late final Set<String> _extensions = {...widget.initial.extensions};

  _SizeUnit _sizeUnit = _SizeUnit.mb;

  final _sizeMin = TextEditingController();
  final _sizeMax = TextEditingController();
  final _widthMin = TextEditingController();
  final _widthMax = TextEditingController();
  final _heightMin = TextEditingController();
  final _heightMax = TextEditingController();
  final _idMin = TextEditingController();
  final _idMax = TextEditingController();

  Timer? _countTimer;
  int _countToken = 0;
  int? _count;

  @override
  void initState() {
    super.initState();
    _fillFromInitial();
    _scheduleCount();
  }

  @override
  void dispose() {
    _countTimer?.cancel();
    for (final controller in [_sizeMin, _sizeMax, _widthMin, _widthMax, _heightMin, _heightMax, _idMin, _idMax]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fillFromInitial() {
    final initial = widget.initial;
    _sizeUnit = _bestUnit(initial.size);
    _sizeMin.text = _formatSize(initial.size?.min);
    _sizeMax.text = _formatSize(initial.size?.max);

    final dimension = initial.dimension ?? const AssistDimension();
    _widthMin.text = _formatInt(dimension.width.min);
    _widthMax.text = _formatInt(dimension.width.max);
    _heightMin.text = _formatInt(dimension.height.min);
    _heightMax.text = _formatInt(dimension.height.max);

    _idMin.text = _formatInt(initial.contentId?.min);
    _idMax.text = _formatInt(initial.contentId?.max);
  }

  // draft

  AssistIntRange? get _sizeRange {
    final min = _bytesOf(_sizeMin);
    final max = _bytesOf(_sizeMax);
    return min == null && max == null ? null : AssistIntRange(min: min, max: max);
  }

  AssistDimension get _dimension => AssistDimension(
        width: AssistIntRange(min: _intOf(_widthMin), max: _intOf(_widthMax)),
        height: AssistIntRange(min: _intOf(_heightMin), max: _intOf(_heightMax)),
      );

  AssistIntRange? get _idRange {
    final min = _intOf(_idMin);
    final max = _intOf(_idMax);
    return min == null && max == null ? null : AssistIntRange(min: min, max: max);
  }

  SearchAssist get _draft => SearchAssist(
        path: widget.initial.path,
        takenDate: _date,
        size: _sizeRange,
        dimension: _dimension.isEmpty ? null : _dimension,
        contentId: _idRange,
        recent: _recent,
        extensions: _extensions,
      );

  /// A bound pair with the lower above the upper is never applied silently.
  bool get _hasInvalidRange {
    bool invalid(AssistIntRange range) {
      final min = range.min;
      final max = range.max;
      return min != null && max != null && min > max;
    }

    final size = _sizeRange;
    final id = _idRange;
    return (size != null && invalid(size)) ||
        (id != null && invalid(id)) ||
        invalid(_dimension.width) ||
        invalid(_dimension.height);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final height = MediaQuery.sizeOf(context).height * .8;
    return SizedBox(
      height: height,
      child: DefaultTabController(
        length: 6,
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: l10n.searchAssistFieldTakenDate),
                Tab(text: l10n.searchAssistFieldSize),
                Tab(text: l10n.searchAssistFieldDimension),
                Tab(text: l10n.searchAssistFieldExtension),
                Tab(text: l10n.searchAssistFieldId),
                Tab(text: l10n.searchAssistFieldRecent),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _tab(_buildDateTab(context)),
                  _tab(_buildSizeTab(context)),
                  _tab(_buildDimensionTab(context)),
                  _tab(_buildExtensionTab(context)),
                  _tab(_buildIdTab(context)),
                  _tab(_buildRecentTab(context)),
                ],
              ),
            ),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _tab(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: child,
      );

  // date

  Widget _buildDateTab(BuildContext context) {
    final l10n = context.l10n;
    final presets = _datePresets();
    final date = _date;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in presets)
              FilterChip(
                label: Text(preset.label),
                selected: date == preset.range,
                onSelected: (_) => _setDate(date == preset.range ? null : preset.range),
              ),
            ActionChip(
              avatar: const Icon(AIcons.date, size: 18),
              label: Text(l10n.searchAssistCustomRange),
              onPressed: _pickDateRange,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          date == null ? l10n.searchAssistDateNone : _formatDateRange(context, date),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  List<({String label, AssistIntRange range})> _datePresets() {
    final l10n = context.l10n;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return [
      (label: l10n.searchAssistDateToday, range: AssistIntRange(min: todayStart.millisecondsSinceEpoch, max: todayEnd.millisecondsSinceEpoch)),
      (
        label: l10n.searchAssistDateLast7Days,
        range: AssistIntRange(
          min: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)).millisecondsSinceEpoch,
          max: todayEnd.millisecondsSinceEpoch,
        ),
      ),
      (
        label: l10n.searchAssistDateThisMonth,
        range: AssistIntRange(min: DateTime(now.year, now.month, 1).millisecondsSinceEpoch, max: todayEnd.millisecondsSinceEpoch),
      ),
      (
        label: l10n.searchAssistDateThisYear,
        range: AssistIntRange(min: DateTime(now.year, 1, 1).millisecondsSinceEpoch, max: todayEnd.millisecondsSinceEpoch),
      ),
    ];
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final current = _date;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: now,
      initialDateRange: current != null
          ? DateTimeRange(
              start: DateTime.fromMillisecondsSinceEpoch(current.min ?? 0),
              end: DateTime.fromMillisecondsSinceEpoch(current.max ?? now.millisecondsSinceEpoch),
            )
          : null,
    );
    if (picked == null) return;
    _setDate(
      AssistIntRange(
        min: DateTime(picked.start.year, picked.start.month, picked.start.day).millisecondsSinceEpoch,
        max: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999).millisecondsSinceEpoch,
      ),
    );
  }

  void _setDate(AssistIntRange? range) {
    setState(() => _date = range);
    _scheduleCount();
  }

  // size

  Widget _buildSizeTab(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(label: Text(l10n.searchAssistSizeSmall), onPressed: () => _setSize(max: 1 << 20)),
            ActionChip(label: Text(l10n.searchAssistSizeMedium), onPressed: () => _setSize(min: 1 << 20, max: 5 << 20)),
            ActionChip(label: Text(l10n.searchAssistSizeLarge), onPressed: () => _setSize(min: 5 << 20)),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _numberField(_sizeMin, l10n.searchAssistMin, decimal: true)),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_sizeMax, l10n.searchAssistMax, decimal: true)),
            const SizedBox(width: 12),
            DropdownButton<_SizeUnit>(
              value: _sizeUnit,
              onChanged: _changeSizeUnit,
              items: [
                for (final unit in _SizeUnit.values) DropdownMenuItem(value: unit, child: Text(unit.label)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildRangeHint(context, _sizeRange, format: (value) => formatFileSize(settings.avesLocale, value)),
      ],
    );
  }

  void _setSize({int? min, int? max}) {
    setState(() {
      _sizeUnit = _SizeUnit.mb;
      _sizeMin.text = _formatSize(min);
      _sizeMax.text = _formatSize(max);
    });
    _scheduleCount();
  }

  void _changeSizeUnit(_SizeUnit? unit) {
    if (unit == null || unit == _sizeUnit) return;
    final previous = _sizeUnit;
    double? convert(TextEditingController controller) {
      final value = double.tryParse(controller.text.trim());
      if (value == null) return null;
      return value * previous.bytes / unit.bytes;
    }

    setState(() {
      _sizeMin.text = _trim(convert(_sizeMin));
      _sizeMax.text = _trim(convert(_sizeMax));
      _sizeUnit = unit;
    });
    _scheduleCount();
  }

  // dimensions

  Widget _buildDimensionTab(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.searchAssistFieldWidth),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _numberField(_widthMin, l10n.searchAssistMin)),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_widthMax, l10n.searchAssistMax)),
          ],
        ),
        const SizedBox(height: 20),
        Text(l10n.searchAssistFieldHeight),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _numberField(_heightMin, l10n.searchAssistMin)),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_heightMax, l10n.searchAssistMax)),
          ],
        ),
        const SizedBox(height: 16),
        Text(l10n.searchAssistDimensionHint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  // extensions

  Widget _buildExtensionTab(BuildContext context) {
    final l10n = context.l10n;
    if (widget.extensions.isEmpty) {
      return Text(l10n.searchAssistExtensionNone);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final extension in widget.extensions)
              FilterChip(
                label: Text(extension.toUpperCase()),
                selected: _extensions.contains(extension.toLowerCase()),
                onSelected: (selected) => _toggleExtension(extension.toLowerCase(), selected),
              ),
          ],
        ),
      ],
    );
  }

  void _toggleExtension(String extension, bool selected) {
    setState(() {
      if (selected) {
        _extensions.add(extension);
      } else {
        _extensions.remove(extension);
      }
    });
    _scheduleCount();
  }

  // id

  Widget _buildIdTab(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _numberField(_idMin, l10n.searchAssistMin)),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_idMax, l10n.searchAssistMax)),
          ],
        ),
        const SizedBox(height: 16),
        Text(l10n.searchAssistIdHint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  // recent

  Widget _buildRecentTab(BuildContext context) {
    final presets = <TimeToNow>[
      const TimeToNow(amount: 1, unit: RelativeTimeUnit.hour),
      const TimeToNow(amount: 3, unit: RelativeTimeUnit.hour),
      const TimeToNow(amount: 12, unit: RelativeTimeUnit.hour),
      const TimeToNow(amount: 1, unit: RelativeTimeUnit.day),
      const TimeToNow(amount: 3, unit: RelativeTimeUnit.day),
      const TimeToNow(amount: 7, unit: RelativeTimeUnit.day),
      const TimeToNow(amount: 30, unit: RelativeTimeUnit.day),
    ];
    final recent = _recent;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in presets)
          ChoiceChip(
            label: Text(_timeToNowLabel(context, preset)),
            selected: recent != null && recent.amount == preset.amount && recent.unit == preset.unit,
            onSelected: (selected) => _setRecent(selected ? AssistRecent(amount: preset.amount, unit: preset.unit) : null),
          ),
      ],
    );
  }

  String _timeToNowLabel(BuildContext context, TimeToNow span) {
    final l10n = context.l10n;
    return switch (span.unit) {
      RelativeTimeUnit.hour => l10n.searchAssistRecentHours(span.amount),
      RelativeTimeUnit.day => l10n.searchAssistRecentDays(span.amount),
    };
  }

  void _setRecent(AssistRecent? value) {
    setState(() => _recent = value);
    _scheduleCount();
  }

  // shared

  Widget _numberField(TextEditingController controller, String label, {bool decimal = false}) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      onChanged: (_) => _scheduleCount(),
    );
  }

  Widget _buildRangeHint(BuildContext context, AssistIntRange? range, {required String Function(int) format}) {
    final theme = Theme.of(context);
    if (range == null) {
      return Text(context.l10n.searchAssistDateNone, style: theme.textTheme.bodySmall);
    }
    final min = range.min;
    final max = range.max;
    final label = min != null && max != null
        ? context.l10n.searchAssistRangeBetween(format(min), format(max))
        : min != null
            ? context.l10n.searchAssistRangeAtLeast(format(min))
            : context.l10n.searchAssistRangeAtMost(format(max!));
    return Text(label, style: theme.textTheme.bodyMedium);
  }

  String _formatDateRange(BuildContext context, AssistIntRange range) {
    final localization = MaterialLocalizations.of(context);
    final min = range.min;
    final max = range.max;
    if (min != null && max != null) {
      return context.l10n.searchAssistRangeBetween(
        localization.formatShortDate(DateTime.fromMillisecondsSinceEpoch(min)),
        localization.formatShortDate(DateTime.fromMillisecondsSinceEpoch(max)),
      );
    }
    final value = min ?? max;
    if (value == null) return '';
    final formatted = localization.formatShortDate(DateTime.fromMillisecondsSinceEpoch(value));
    return min != null ? context.l10n.searchAssistRangeAtLeast(formatted) : context.l10n.searchAssistRangeAtMost(formatted);
  }

  Widget _buildActions(BuildContext context) {
    final l10n = context.l10n;
    final count = _count;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
        child: Row(
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context, widget.initial.clearOther()),
              child: Text(l10n.searchAssistClear),
            ),
            const Spacer(),
            if (count != null) ...[
              Text(l10n.searchAssistMatchCount(count), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 12),
            ],
            FilledButton(
              onPressed: _hasInvalidRange ? null : () => Navigator.pop(context, _draft),
              child: Text(l10n.searchAssistConfirm),
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleCount() {
    _countTimer?.cancel();
    _countTimer = Timer(const Duration(milliseconds: 300), _runCount);
  }

  Future<void> _runCount() async {
    final token = ++_countToken;
    final count = await AssistCounter.count(_draft.toFilters(calendar: widget.calendar));
    if (!mounted || token != _countToken) return;
    setState(() => _count = count);
  }

  // parsing / formatting

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    return _trim(bytes / _sizeUnit.bytes);
  }

  /// The largest unit that represents the stored bounds exactly, so reopening
  /// the sheet never rounds a size the user already set.
  _SizeUnit _bestUnit(AssistIntRange? range) {
    final bytes = range?.min ?? range?.max;
    if (bytes == null) return _SizeUnit.mb;
    for (final unit in [_SizeUnit.gb, _SizeUnit.mb, _SizeUnit.kb]) {
      if (bytes % unit.bytes == 0) return unit;
    }
    return _SizeUnit.kb;
  }

  String _trim(double? value) {
    if (value == null) return '';
    final rounded = (value * 100).round() / 100;
    return rounded == rounded.roundToDouble() ? '${rounded.round()}' : '$rounded';
  }

  String _formatInt(int? value) => value?.toString() ?? '';

  int? _intOf(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value == null || value < 0 ? null : value;
  }

  int? _bytesOf(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim());
    if (value == null || value <= 0) return null;
    return (value * _sizeUnit.bytes).round();
  }
}
