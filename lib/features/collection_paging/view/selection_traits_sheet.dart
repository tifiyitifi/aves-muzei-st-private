import 'package:aves/features/collection_paging/selection/selection_mark.dart';
import 'package:aves/features/collection_paging/selection/selection_trait.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/rating.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/dialogs/pick_dialogs/tag_pick_page.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/single_selection.dart';
import 'package:aves/widgets/filter_grids/common/enums.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Opens the sheet that drives a marked selection's trait history.
///
/// The selection is read here, from the page's own context: the dialog lives in
/// its own route, where the collection page's providers are out of reach.
Future<void> showSelectionTraitsSheet(BuildContext context, CollectionSelectionMark mark) {
  final selection = context.read<Selection<AvesEntry>>();
  return showAvesDialog<void>(
    context: context,
    builder: (context) => _SelectionTraitsDialog(mark: mark, selection: selection),
    routeSettings: const RouteSettings(name: _SelectionTraitsDialog.routeName),
  );
}

/// The trait sheet: the ops applied so far, each undoable, and the traits the
/// whole view can be selected or deselected by.
///
/// Traits are reached as *filters* — the same objects a view is built from — so
/// a trait and a view filter can never mean different rows. Albums and dates are
/// not offered here: their sections already carry a toggle of their own.
class _SelectionTraitsDialog extends StatefulWidget {
  static const routeName = '/dialog/selection_traits';

  final CollectionSelectionMark mark;
  final Selection<AvesEntry> selection;

  const new({required this.mark, required this.selection});

  @override
  State<_SelectionTraitsDialog> createState() => _SelectionTraitsDialogState();
}

class _SelectionTraitsDialogState extends State<_SelectionTraitsDialog> {
  CollectionSelectionMark get mark => widget.mark;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  /// Deselecting every trait empties the mark, and an emptied mark leaves
  /// selection mode: the sheet has nothing left to drive.
  void _onSelectionChanged() {
    if (!widget.selection.isSelecting) Navigator.maybeOf(context)?.pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: mark,
      builder: (context, _) {
        final ops = mark.ops;
        return AvesDialog(
          title: context.l10n.menuActionSelectByTrait,
          scrollableContent: [
            for (final op in ops.reversed) _TraitOpRow(mark: mark, op: op),
            if (ops.isNotEmpty) const Divider(),
            _TraitAddRow(mark: mark, kind: _TraitKind.tag),
            _TraitAddRow(mark: mark, kind: _TraitKind.rating),
            _TraitAddRow(mark: mark, kind: _TraitKind.location),
          ],
          actions: [
            CancelButton<void>(text: MaterialLocalizations.of(context).closeButtonTooltip),
          ],
        );
      },
    );
  }
}

/// One trait op, with the action that undoes it.
class _TraitOpRow extends StatelessWidget {
  final CollectionSelectionMark mark;
  final SelectionTraitOp op;

  const new({required this.mark, required this.op});

  @override
  Widget build(BuildContext context) {
    final select = op.select;
    return ListTile(
      dense: true,
      leading: Icon(select ? AIcons.selected : AIcons.unselected),
      title: Text(op.label, overflow: .ellipsis, maxLines: 2),
      trailing: TextButton(
        // Undoing an op is appending its opposite, which never changes what the
        // ops added after it mean.
        onPressed: () => select ? mark.deselectTrait(op.trait, label: op.label) : mark.selectTrait(op.trait, label: op.label),
        child: Text(context.l10n.collectionSelectionTraitUndo),
      ),
    );
  }
}

/// A trait family, and the picker that offers one trait of it.
enum _TraitKind { tag, rating, location }

extension on _TraitKind {
  IconData get icon => switch (this) {
        .tag => AIcons.tag,
        .rating => AIcons.rating,
        .location => AIcons.location,
      };

  String title(BuildContext context) => switch (this) {
        .tag => context.l10n.tagPageTitle,
        .rating => context.l10n.searchRatingSectionTitle,
        .location => context.l10n.editEntryLocationDialogTitle,
      };

  /// The trait to add, or null when the user backs out.
  Future<CollectionFilter?> pick(BuildContext context) => switch (this) {
        .tag => pickTag(context: context, chipTypes: const {ChipType.regular}, initialGroup: null),
        .rating => _pickRating(context),
        .location => _pickLocation(context),
      };

  Future<CollectionFilter?> _pickRating(BuildContext context) => showAvesDialog<int>(
        context: context,
        builder: (context) => AvesSingleSelectionDialog<int>(
          initialValue: 0,
          options: {for (var rating = 5; rating >= 0; rating--) rating: RatingFilter.formatRating(context, rating)},
        ),
        routeSettings: const RouteSettings(name: AvesSingleSelectionDialog.routeName),
      ).then((rating) => rating != null ? RatingFilter(rating) : null);

  /// Countries, states and places in one list: they are the same kind of trait,
  /// and the summary domain already holds them all for the filter bar.
  Future<CollectionFilter?> _pickLocation(BuildContext context) async {
    final source = context.read<CollectionSource>();
    // An entry-free (paged) source fills its location summaries on first touch:
    // await them so the picker opens on data instead of an empty list.
    await source.summaries?.ensureLocations();
    if (!context.mounted) return null;

    final options = <LocationFilter, String>{};
    void add(LocationLevel level, Iterable<String> values) {
      for (final value in values) {
        final filter = LocationFilter(level, value);
        options[filter] = filter.getLabel(context);
      }
    }

    add(LocationLevel.country, source.sortedCountries);
    add(LocationLevel.state, source.sortedStates);
    add(LocationLevel.place, source.sortedPlaces);
    if (options.isEmpty) return Future.value(null);

    return showAvesDialog<LocationFilter>(
      context: context,
      builder: (context) => AvesSingleSelectionDialog<LocationFilter>(
        initialValue: options.keys.first,
        options: options,
      ),
      routeSettings: const RouteSettings(name: AvesSingleSelectionDialog.routeName),
    );
  }
}

/// One trait family row, offering both directions.
class _TraitAddRow extends StatefulWidget {
  final CollectionSelectionMark mark;
  final _TraitKind kind;

  const new({required this.mark, required this.kind});

  @override
  State<_TraitAddRow> createState() => _TraitAddRowState();
}

class _TraitAddRowState extends State<_TraitAddRow> with FeedbackMixin {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      dense: true,
      leading: Icon(widget.kind.icon),
      title: Text(widget.kind.title(context)),
      trailing: Row(
        mainAxisSize: .min,
        children: [
          TextButton(
            onPressed: () => _add(select: true),
            child: Text(l10n.menuActionSelect),
          ),
          TextButton(
            onPressed: () => _add(select: false),
            child: Text(l10n.collectionSelectionTraitDeselect),
          ),
        ],
      ),
    );
  }

  Future<void> _add({required bool select}) async {
    final filter = await widget.kind.pick(context);
    if (filter == null || !mounted) return;
    final trait = SelectionTrait.fromFilter(filter);
    if (trait == null) {
      // No SQL translation: the trait cannot be part of a marked selection
      // without enumerating the rows it matches.
      showFeedback(context, FeedbackType.warn, context.l10n.genericFailureFeedback);
      return;
    }
    final label = filter.getLabel(context);
    if (select) {
      widget.mark.selectTrait(trait, label: label);
    } else {
      widget.mark.deselectTrait(trait, label: label);
    }
  }
}
