package com.dot.gallery.feature_node.presentation.mediaview.components.media

/**
 * Which interactive cutout prompt tool is active.
 *
 * Upstream declares this next to the media viewer's cutout overlay; the editor shares the same
 * session state, so it lives with [CutoutState] here.
 */
enum class ZoomablePagerImagePointTool { NONE, ADD, REMOVE }
