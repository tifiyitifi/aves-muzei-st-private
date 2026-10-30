import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_write_back.dart';
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
    'visibleRangeGallery' => l10n.visibleRangeGallery,
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
    'visibleRangePresetCameraRecent6h' => l10n.visibleRangePresetCameraRecent6h,
    'visibleRangePresetRecent6h' => l10n.visibleRangePresetRecent6h,
    'visibleRangePresetRecent12h' => l10n.visibleRangePresetRecent12h,
    'visibleRangePresetRecent7d' => l10n.visibleRangePresetRecent7d,
    'visibleRangePresetAnimated' => l10n.visibleRangePresetAnimated,
    'visibleRangePresetNotCamera' => l10n.visibleRangePresetNotCamera,
    'visibleRangePresetNotPortrait' => l10n.visibleRangePresetNotPortrait,
    'visibleRangePresetNotLandscape' => l10n.visibleRangePresetNotLandscape,
    // Bundled wallpaper-group names double as their range's base name, so the
    // same switch resolves both (the group page stores `@wallpaperGroupDefault*`).
    'wallpaperGroupNone' => l10n.wallpaperGroupNone,
    'wallpaperGroupAllImages' => l10n.wallpaperGroupAllImages,
    'wallpaperGroupSectionNone' => l10n.wallpaperGroupSectionNone,
    'wallpaperGroupDefaultAll' => l10n.wallpaperGroupDefaultAll,
    'wallpaperGroupDefaultDcim' => l10n.wallpaperGroupDefaultDcim,
    'wallpaperGroupDefaultPictures' => l10n.wallpaperGroupDefaultPictures,
    // An unknown key is a data error, but showing it beats an empty tile.
    _ => key,
  };
}

/// The range part of a group card: the base name when it is not the group's own
/// name, followed by how many extra restrictions apply.
///
/// A bundled group's base is spelled exactly like the group (`Pictures`), so
/// repeating it would take the card's whole line and push the image count out;
/// only a range that actually differs (a renamed group, or another base) is
/// named. Supplements never count, because they never narrow the result.
String visibleRangeGroupSummary(BuildContext context, {required VisibleRange? range, required String groupName, required bool isNone}) {
  final l10n = context.l10n;
  if (range == null) return '';
  final restrictions = range.activeRulesOf(VisibleRangeRuleKind.restriction).length;
  // An empty, unused base is 「no base」, not a base called "All images": group 3
  // stores exactly that, and naming it would only take the card's line.
  final showBase = !isNone && !range.isBaseUnrestricted && range.baseName != groupName;
  if (showBase) {
    final base = _baseLabel(context, range);
    return restrictions == 0 ? base : l10n.wallpaperGroupRangeRules(base, restrictions);
  }
  return restrictions == 0 ? '' : l10n.wallpaperGroupRangeRestrictions(restrictions);
}

/// A range's base name: its bundled or user name, else its filters' labels.
String _baseLabel(BuildContext context, VisibleRange range) {
  final name = range.baseName;
  if (name.startsWith('@')) return visibleRangePresetLabel(context, name.substring(1));
  if (name.isNotEmpty) return name;
  final filters = visibleRangeFilterLabels(context, range.baseFilters);
  return filters.isEmpty ? context.l10n.wallpaperGroupAllImages : filters;
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

/// The name of a remembered write-back target: a rule's own name, or the base
/// range's name, falling back to the filters' labels when it was never named.
String visibleRangeWriteBackTargetLabel(BuildContext context, VisibleRangeWriteBackTarget target) {
  final label = target.label;
  if (label.startsWith('@')) return visibleRangePresetLabel(context, label.substring(1));
  if (label.isNotEmpty) return label;
  final filters = visibleRangeFilterLabels(context, target.filters);
  if (filters.isNotEmpty) return filters;
  return context.l10n.visibleRangePinGroupBase;
}

/// The owner of a target followed by what it is, e.g. "Group 2 · Pictures ·
/// Restriction". The gallery is named from ARB; a group keeps its own name.
String visibleRangeWriteBackTargetLine(BuildContext context, VisibleRangeWriteBackTarget target) {
  final l10n = context.l10n;
  final owner = target.isGallery ? l10n.visibleRangePinTargetGallery : l10n.visibleRangeOwnerWithNumber(target.number, _groupName(context, target));
  final kind = switch (target.kind) {
    VisibleRangeCandidateKind.base => l10n.visibleRangePinGroupBase,
    VisibleRangeCandidateKind.restriction => l10n.visibleRangePinGroupRestriction,
    VisibleRangeCandidateKind.supplement => l10n.visibleRangePinGroupSupplement,
  };
  return l10n.visibleRangeWriteBackTargetLine(owner, kind);
}

String _groupName(BuildContext context, VisibleRangeWriteBackTarget target) {
  final name = target.ownerName;
  if (name.startsWith('@')) return visibleRangePresetLabel(context, name.substring(1));
  if (name.isNotEmpty) return name;
  return context.l10n.wallpaperGroupFallbackName(target.number);
}
