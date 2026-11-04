import 'package:aves/features/media_ops/model/media_op_engine.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';

/// Localized name of a media operation engine, shared by the v1 list and the v2
/// surface.
String mediaOpEngineName(BuildContext context, MediaOpEngine engine) => switch (engine) {
      MediaOpEngine.v1 => context.l10n.mediaOpEngineV1Name,
      MediaOpEngine.v2 => context.l10n.mediaOpEngineV2Name,
    };

/// Localized description of a media operation engine, shown for the
/// non-current options.
String mediaOpEngineDescription(BuildContext context, MediaOpEngine engine) => switch (engine) {
      MediaOpEngine.v1 => context.l10n.mediaOpEngineV1Description,
      MediaOpEngine.v2 => context.l10n.mediaOpEngineV2Description,
    };
