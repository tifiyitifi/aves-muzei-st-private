import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:flutter/foundation.dart';

/// What the user chose when asked about cataloguing a large backlog.
enum CatalogPromptAnswer {
  /// Catalogue now, and ask again for a future backlog.
  catalogueNow,

  /// Skip the sweep for this session; ask again next time.
  notNow,

  /// Catalogue now and stop asking.
  alwaysCatalogue,
}

/// The one question the background catalogue asks, and the session state that
/// keeps it from repeating.
///
/// Cataloguing a huge library is long invisible work, so it does not start
/// silently: the paged lens raises this question the first time it resolves a
/// collection with a backlog worth mentioning. The lens only raises it — the UI
/// layer owns dialogs — so the question travels through [pending].
class CatalogPrompt {
  /// A backlog below this many rows is not worth a question: the sweep would
  /// finish before the user could read the dialog.
  static const int threshold = 2000;

  /// The uncatalogued row count awaiting an answer, or null when nothing is
  /// pending.
  final ValueNotifier<int?> pending = ValueNotifier(null);

  bool _askedThisSession = false;

  /// Whether the question should be raised instead of starting the sweep.
  ///
  /// Pure, so the lens and its tests share one definition: a user who opted out,
  /// an already-asked session and a small backlog all start the sweep directly.
  bool shouldAsk({required bool askBeforeCatalog, required int uncatalogued}) => askBeforeCatalog && !_askedThisSession && uncatalogued > threshold;

  /// Records that the question was raised. It is asked at most once per session,
  /// whether or not the dialog is answered, so dismissing it cannot loop.
  void markAsked(int uncatalogued) {
    _askedThisSession = true;
    pending.value = uncatalogued;
  }

  /// Clears the pending question, once the dialog has taken it over.
  void resolve() => pending.value = null;

  /// Forgets the session's question, for tests and a fresh session.
  @visibleForTesting
  void resetSession() {
    _askedThisSession = false;
    pending.value = null;
  }
}

/// Applies the user's answer and reports whether the backlog should run now.
///
/// "Don't ask again" also flips the setting, which the settings surface can turn
/// back on, so the choice stays reversible.
Future<bool> applyCatalogPromptAnswer(CatalogPromptAnswer answer) async {
  switch (answer) {
    case CatalogPromptAnswer.catalogueNow:
      return true;
    case CatalogPromptAnswer.alwaysCatalogue:
      await collectionPagingPrefs.setAskBeforeCatalog(false);
      return true;
    case CatalogPromptAnswer.notNow:
      return false;
  }
}

/// The app-wide question (mirrors the `collectionPagingPrefs` singleton style).
final CatalogPrompt catalogPrompt = CatalogPrompt();
