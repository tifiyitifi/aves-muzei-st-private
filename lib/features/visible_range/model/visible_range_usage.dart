import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// One target the user has applied to a media set, remembered for write-back.
///
/// A rule id is global and never reused, so it identifies its rule on its own.
/// A base has no id (the range owns it), hence the `base.<rangeId>` form. The
/// kind is kept beside the id so the write-back list can say what the target is
/// without loading every range first.
@immutable
class VisibleRangeRuleUsage extends Equatable {
  final String id;
  final String rangeId;

  /// Rule id, or empty for a base target.
  final String targetId;
  final VisibleRangeCandidateKind kind;
  final int usedAt;

  const new({
    required this.id,
    required this.rangeId,
    required this.kind,
    required this.usedAt,
    this.targetId = '',
  });

  /// Usage of a rule; [ruleId] is the rule's own global id.
  factory forRule({required String ruleId, required String rangeId, required VisibleRangeRuleKind kind, required int usedAt}) => VisibleRangeRuleUsage(
        id: ruleUsageId(ruleId),
        rangeId: rangeId,
        targetId: ruleId,
        kind: kind == VisibleRangeRuleKind.restriction ? VisibleRangeCandidateKind.restriction : VisibleRangeCandidateKind.supplement,
        usedAt: usedAt,
      );

  /// Usage of a range's own base.
  factory forBase({required String rangeId, required int usedAt}) => VisibleRangeRuleUsage(
        id: baseUsageId(rangeId),
        rangeId: rangeId,
        kind: VisibleRangeCandidateKind.base,
        usedAt: usedAt,
      );

  bool get isBase => kind == VisibleRangeCandidateKind.base;

  @override
  List<Object?> get props => [id, rangeId, targetId, kind, usedAt];
}

/// Usage id of a rule target.
String ruleUsageId(String ruleId) => 'rule.$ruleId';

/// Usage id of a range's base target.
String baseUsageId(String rangeId) => 'base.$rangeId';
