import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';

/// UI metadata for one native batch tool.
///
/// Kept in the view layer so the model stays free of icons and localized text.
/// [creatableFromRunSheet] is false for tools that only come from a saved recipe.
class BatchToolInfo {
  final BatchToolKind kind;
  final String Function(BuildContext context) title;
  final String Function(BuildContext context) description;
  final IconData icon;
  final BatchAction Function() createDefault;
  final bool creatableFromRunSheet;

  const new({
    required this.kind,
    required this.title,
    required this.description,
    required this.icon,
    required this.createDefault,
    this.creatableFromRunSheet = true,
  });
}

final List<BatchToolInfo> batchToolCatalog = [
  BatchToolInfo(
    kind: BatchToolKind.filter,
    title: (context) => context.l10n.batchToolFilter,
    description: (context) => context.l10n.batchToolFilterDescription,
    icon: AIcons.palette,
    createDefault: () => BatchActions.filter('Vintage'),
  ),
  BatchToolInfo(
    kind: BatchToolKind.adjust,
    title: (context) => context.l10n.batchToolAdjust,
    description: (context) => context.l10n.batchToolAdjustDescription,
    icon: AIcons.settings,
    createDefault: () => BatchActions.adjust('Brightness', value: 0.1),
  ),
  BatchToolInfo(
    kind: BatchToolKind.rotate,
    title: (context) => context.l10n.batchToolRotate,
    description: (context) => context.l10n.batchToolRotateDescription,
    icon: AIcons.rotateLeft,
    createDefault: BatchActions.rotate,
  ),
  BatchToolInfo(
    kind: BatchToolKind.flip,
    title: (context) => context.l10n.batchToolFlip,
    description: (context) => context.l10n.batchToolFlipDescription,
    icon: AIcons.flip,
    createDefault: BatchActions.flip,
  ),
  BatchToolInfo(
    kind: BatchToolKind.crop,
    title: (context) => context.l10n.batchToolCrop,
    description: (context) => context.l10n.batchToolCropDescription,
    icon: AIcons.aspectRatioFree,
    createDefault: BatchActions.crop,
  ),
  BatchToolInfo(
    kind: BatchToolKind.resize,
    title: (context) => context.l10n.batchToolResize,
    description: (context) => context.l10n.batchToolResizeDescription,
    icon: AIcons.width,
    createDefault: () => BatchActions.resize(maxLongEdge: 2048),
  ),
  BatchToolInfo(
    kind: BatchToolKind.convert,
    title: (context) => context.l10n.batchToolConvert,
    description: (context) => context.l10n.batchToolConvertDescription,
    icon: AIcons.convert,
    createDefault: BatchActions.convert,
  ),
  BatchToolInfo(
    kind: BatchToolKind.footer,
    title: (context) => context.l10n.batchToolFooter,
    description: (context) => context.l10n.batchToolFooterDescription,
    icon: AIcons.text,
    createDefault: BatchActions.footer,
  ),
  BatchToolInfo(
    kind: BatchToolKind.refreshTime,
    title: (context) => context.l10n.batchToolRefreshTime,
    description: (context) => context.l10n.batchToolRefreshTimeDescription,
    icon: AIcons.date,
    createDefault: BatchActions.refreshTime,
  ),
  BatchToolInfo(
    kind: BatchToolKind.recipe,
    title: (context) => context.l10n.batchToolRecipe,
    description: (context) => context.l10n.batchToolRecipeDescription,
    icon: AIcons.edit,
    createDefault: () => BatchActions.recipe(const []),
    creatableFromRunSheet: false,
  ),
];

BatchToolInfo batchToolInfo(BatchToolKind kind) => batchToolCatalog.firstWhere((info) => info.kind == kind);

/// The subset the run sheet can enable and configure.
final List<BatchToolInfo> batchRunnableCatalog = batchToolCatalog.where((info) => info.creatableFromRunSheet).toList(growable: false);
