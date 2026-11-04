package com.dot.gallery.feature_node.presentation.util

import android.util.Log

/**
 * Logging helpers kept under the upstream names so the ported editor sources stay unchanged.
 *
 * The editor is native Kotlin, outside the Dart `lib/features/logging` facade; calls stay
 * fire-and-forget so logging can never break an edit or save.
 */
private const val TAG = "RefraEditor"

private fun logcat(block: () -> Int) {
    runCatching { block() }
}

fun printInfo(message: Any) {
    logcat { Log.i(TAG, message.toString()) }
}

fun printInfo(tag: String, message: String) {
    logcat { Log.i(tag, message) }
}

fun printDebug(message: Any) {
    logcat { Log.d(TAG, message.toString()) }
}

fun printDebug(tag: String, message: String) {
    logcat { Log.d(tag, message) }
}

fun printError(message: String) {
    logcat { Log.e(TAG, message) }
}

fun printError(
    tag: String,
    message: String,
    throwable: Throwable? = null,
) {
    logcat { Log.e(tag, message, throwable) }
}

fun printWarning(message: String) {
    logcat { Log.w(TAG, message) }
}

fun printWarn(
    tag: String,
    message: String,
    @Suppress("UNUSED_PARAMETER") ctx: Map<String, String>? = null,
    @Suppress("UNUSED_PARAMETER") scope: String? = null,
) {
    logcat { Log.w(tag, message) }
}
