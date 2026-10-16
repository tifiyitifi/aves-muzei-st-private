import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';

/// Localized name of a collection engine, shared by the v1 list and the v2 surface.
String collectionEngineName(BuildContext context, CollectionEngine engine) => switch (engine) {
      CollectionEngine.legacy => context.l10n.collectionEngineLegacy,
      CollectionEngine.paged => context.l10n.collectionEnginePaged,
    };
