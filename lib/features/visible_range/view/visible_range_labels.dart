import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/model/visible_range_write_back.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
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
  final sources = range.activeRulesOf(VisibleRangeRuleKind.source);
  final restrictions = range.activeRulesOf(VisibleRangeRuleKind.restriction).length;
  final singleLabel = sources.length == 1 ? visibleRangeRuleLabel(context, sources.first) : null;
  // The caller may pass a bundled name as its ARB key; compare displayed names.
  final groupLabel = groupName.startsWith('@') ? visibleRangePresetLabel(context, groupName.substring(1)) : groupName;
  // A group with no source is 「no source」, and a bundled source spelled exactly
  // like the group ("Pictures") would only take the card's line.
  final showSource = !isNone && sources.isNotEmpty && singleLabel != groupLabel;
  if (showSource) {
    final source = singleLabel ?? sources.map((rule) => visibleRangeRuleLabel(context, rule)).where((label) => label.isNotEmpty).join(' · ');
    return restrictions == 0 ? source : l10n.wallpaperGroupRangeRules(source, restrictions);
  }
  return restrictions == 0 ? '' : l10n.wallpaperGroupRangeRestrictions(restrictions);
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
  if (candidate.isGroup) {
    final group = visibleRangeController.galleryGroupById(candidate.groupId);
    final name = _groupFallbackName(context, candidate.groupId);
    // A group tile names the group and, when they differ, what its own
    // conditions add: the cover and count alone do not say whether a restriction
    // is what makes the group look like this.
    final summary = visibleRangeGroupSummary(
      context,
      range: group,
      groupName: group?.name ?? '',
      isNone: candidate.groupId == VisibleRange.galleryRangeId,
    );
    return summary.isEmpty ? name : '$name · $summary';
  }
  return visibleRangeFilterLabels(context, candidate.filters);
}

String _groupFallbackName(BuildContext context, String groupId) {
  final number = visibleRangeController.galleryGroupNumber(groupId);
  return number > 0 ? context.l10n.wallpaperGroupFallbackName(number) : context.l10n.visibleRangeUnrestricted;
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

/// Every place a confirmation writes: the groups receiving the filters followed
/// by the rules being overwritten. Both halves read the same selections the
/// confirmation itself uses, so the folded sheet cannot promise a location the
/// save will not touch.
String visibleRangeExpectedWrites(
  BuildContext context, {
  required List<VisibleRangePinTarget> pinTargets,
  required Set<String> selectedPinIds,
  required List<VisibleRangeWriteBackTarget> writeBackTargets,
  required Set<String> selectedUsageIds,
  VisibleRangeRuleKind? forcedRole,
}) {
  final lines = [
    for (final target in pinTargets)
      if (selectedPinIds.contains(target.id)) visibleRangePinTargetLine(context, target, forcedRole: forcedRole),
    for (final target in writeBackTargets)
      if (selectedUsageIds.contains(target.usageId)) visibleRangeWriteBackTargetLine(context, target),
  ];
  return lines.isEmpty ? context.l10n.visibleRangeWriteBackNone : lines.join('\n');
}

/// The location of one pin, named by owner and — when the role is known — what
/// is written there. An automatic split has no single role, so it names only the
/// owner; the outside pool always writes one fixed role.
String visibleRangePinTargetLine(BuildContext context, VisibleRangePinTarget target, {VisibleRangeRuleKind? forcedRole}) {
  final l10n = context.l10n;
  final label = target.name.startsWith('@') ? visibleRangePresetLabel(context, target.name.substring(1)) : target.name;
  final name = label.isEmpty ? l10n.wallpaperGroupFallbackName(target.number) : label;
  final owner = switch (target.kind) {
    VisibleRangePinTargetKind.outside => l10n.visibleRangePinGroupOutside,
    VisibleRangePinTargetKind.galleryGroup => target.number > 0 ? l10n.visibleRangeOwnerWithNumber(target.number, name) : l10n.visibleRangeUnrestricted,
    VisibleRangePinTargetKind.wallpaperGroup => l10n.visibleRangePinTargetWallpaperOwner(name),
  };
  final role = switch (target.kind) {
    VisibleRangePinTargetKind.outside => target.role,
    VisibleRangePinTargetKind.galleryGroup || VisibleRangePinTargetKind.wallpaperGroup => forcedRole,
  };
  return role == null ? owner : l10n.visibleRangeWriteBackTargetLine(owner, visibleRangeRuleKindLabel(context, role));
}

/// The short role name shared by the role menu, the write-back lines and the
/// expected write locations, so they never spell the same role differently.
String visibleRangeRuleKindLabel(BuildContext context, VisibleRangeRuleKind kind) {
  final l10n = context.l10n;
  return switch (kind) {
    VisibleRangeRuleKind.source => l10n.visibleRangePinGroupBase,
    VisibleRangeRuleKind.restriction => l10n.visibleRangePinGroupRestriction,
    VisibleRangeRuleKind.supplement => l10n.visibleRangePinGroupSupplement,
  };
}

/// The owner of a target followed by what it is, e.g. "Group 2 · Pictures ·
/// Restriction". The gallery is named from ARB; a group keeps its own name.
String visibleRangeWriteBackTargetLine(BuildContext context, VisibleRangeWriteBackTarget target) {
  final l10n = context.l10n;
  // A numbered target is a gallery group; number 0 is the scope-wide outside
  // pool, which has no group name of its own.
  final owner = target.number > 0
      ? l10n.visibleRangeOwnerWithNumber(target.number, _groupName(context, target))
      : target.isGallery
          ? l10n.visibleRangePinGroupOutside
          : l10n.visibleRangePinTargetGallery;
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
