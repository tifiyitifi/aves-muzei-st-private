package com.dot.gallery.feature_node.domain.util

import android.net.Uri
import com.dot.gallery.feature_node.domain.model.Media

private val RAW_EXTENSIONS = setOf(
    "3fr", "ari", "arw", "bay", "cr2", "cr3", "crw", "dcr", "dng", "erf", "fff", "gpr",
    "iiq", "k25", "kdc", "mef", "mos", "mrw", "nef", "nrw", "orf", "pef", "raf", "raw",
    "rw2", "rwl", "sr2", "srf", "srw", "x3f",
)

val Media.isRaw: Boolean
    get() = (mimeType.isNotBlank() &&
            (mimeType.startsWith("image/x-") || mimeType.startsWith("image/vnd."))) ||
            label.substringAfterLast('.', "").lowercase() in RAW_EXTENSIONS

/**
 * The staged edit copies are always plain media rows owned by this app, so encrypted media
 * never reaches the editor; keeping the check explicit avoids leaking the concept.
 */
val Media.isEncrypted: Boolean
    get() = false

fun <T : Media> T.getUri(): Uri = when (this) {
    is Media.UriMedia -> uri
    else -> throw IllegalArgumentException("Media type ${this.javaClass.simpleName} not supported")
}
