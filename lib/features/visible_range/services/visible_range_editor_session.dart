import 'dart:async';

import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:flutter/foundation.dart';

/// The group editor's session: which group the page edits, its unsaved draft,
/// and when it opened.
///
/// The session is in-memory, like the wallpaper page's: leaving the page keeps
/// its bar entry (and the draft) until the page is closed, and a process restart
/// starts closed. [openedAt] orders the derived bar entries: the one opened first
/// sits nearest the visible-range entry.
class VisibleRangeEditorSession extends ChangeNotifier {
  String? _groupId;
  VisibleRange? _draft;
  int _openedAt = 0;

  String? get groupId => _groupId;

  bool get active => _groupId != null;

  int get openedAt => _openedAt;

  /// The unsaved draft, kept across a bottom-bar visit.
  VisibleRange? get draft => _draft;

  void open(String groupId, VisibleRange draft) {
    final keepsDraft = _groupId == groupId && _draft != null;
    final wasActive = _groupId != null;
    _groupId = groupId;
    if (!keepsDraft) _draft = draft;
    // The bar order is the first open, not the last visit: re-entering an open
    // session must not move its entry outward.
    if (!wasActive) _openedAt = nextForkSessionTick();
    _notifyDeferred();
  }

  /// Replaces the draft without notifying: the page that owns it rebuilds
  /// itself, and the bar has nothing to change.
  void setDraft(VisibleRange draft) => _draft = draft;

  void close() {
    if (_groupId == null) return;
    _groupId = null;
    _draft = null;
    _notifyDeferred();
  }

  /// Notifies after the current build instead of inside it.
  ///
  /// The session opens while the Navigator builds its routes, when the bottom
  /// bar may already have been built this frame.
  void _notifyDeferred() => scheduleMicrotask(notifyListeners);
}

int _forkSessionClock = 0;

/// One monotonic tick per opened fork page, shared by the wallpaper page and the
/// group editor so their derived bar entries can be ordered by open time.
int nextForkSessionTick() => ++_forkSessionClock;

/// The process-wide editor session.
final visibleRangeEditorSession = VisibleRangeEditorSession();
