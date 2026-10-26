import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';

/// Localizes a built-in candidate name.
///
/// Built-in presets store their ARB key in `name`, and materialized default
/// rules store it with a leading `@`. Keeping one switch means a new default
/// only needs its JSON entry and ARB key, not another label helper.
String visibleRangePresetLabel(BuildContext context, String key) {
  final l10n = context.l10n;
  return switch (key) {
    'visibleRangeUnrestricted' => l10n.visibleRangeUnrestricted,
    'visibleRangePresetImage' => l10n.visibleRangePresetImage,
    'visibleRangePresetVideo' => l10n.visibleRangePresetVideo,
    'visibleRangePresetNotVideo' => l10n.visibleRangePresetNotVideo,
    'visibleRangePresetFavourite' => l10n.visibleRangePresetFavourite,
    'visibleRangePresetRating5' => l10n.visibleRangePresetRating5,
    'visibleRangePresetRating4' => l10n.visibleRangePresetRating4,
    'visibleRangePresetRating3' => l10n.visibleRangePresetRating3,
    'visibleRangePresetPortrait' => l10n.visibleRangePresetPortrait,
    'visibleRangePresetLandscape' => l10n.visibleRangePresetLandscape,
    'visibleRangePresetPanorama' => l10n.visibleRangePresetPanorama,
    'visibleRangePresetRaw' => l10n.visibleRangePresetRaw,
    'visibleRangePresetMotionPhoto' => l10n.visibleRangePresetMotionPhoto,
    'visibleRangePresetCamera' => l10n.visibleRangePresetCamera,
    'visibleRangePresetPictures' => l10n.visibleRangePresetPictures,
    'visibleRangePresetCameraRecent3h' => l10n.visibleRangePresetCameraRecent3h,
    'visibleRangePresetRecent3h' => l10n.visibleRangePresetRecent3h,
    'visibleRangePresetRecent12h' => l10n.visibleRangePresetRecent12h,
    'visibleRangePresetRecent3d' => l10n.visibleRangePresetRecent3d,
    'visibleRangePresetAnimated' => l10n.visibleRangePresetAnimated,
    'visibleRangePresetNotCamera' => l10n.visibleRangePresetNotCamera,
    'visibleRangePresetNotPortrait' => l10n.visibleRangePresetNotPortrait,
    'visibleRangePresetNotLandscape' => l10n.visibleRangePresetNotLandscape,
    // An unknown key is a data error, but showing it beats an empty tile.
    _ => key,
  };
}

/// The label of a rule: a localized default name, the user's rename, or the
/// filters' own labels when the rule was never named.
String visibleRangeRuleLabel(BuildContext context, VisibleRangeRule rule) {
  final label = rule.label;
  if (label.startsWith('@')) return visibleRangePresetLabel(context, label.substring(1));
  if (label.isNotEmpty) return label;
  return visibleRangeFilterLabels(context, rule.filters);
}

String visibleRangeFilterLabels(BuildContext context, Set<CollectionFilter> filters) {
  final labels = filters.map((filter) => filter.getLabel(context)).where((label) => label.isNotEmpty).toSet().toList()..sort();
  return labels.join(' · ');
}

String visibleRangeCandidateLabel(BuildContext context, VisibleRangeCandidate candidate) {
  if (candidate.labelKey.isNotEmpty) return visibleRangePresetLabel(context, candidate.labelKey);
  if (candidate.label.isNotEmpty) return candidate.label;
  return visibleRangeFilterLabels(context, candidate.filters);
}
