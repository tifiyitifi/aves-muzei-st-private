/*
 * SPDX-FileCopyrightText: 2023 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package com.dot.gallery.core.util.ext

import android.database.Cursor
import androidx.core.database.getLongOrNull
import androidx.core.database.getStringOrNull

/**
 * Cursor mapping helpers used by the editor's media queries.
 *
 * Upstream also exposes `Resource`-wrapping flows and startup tracing in this file; the fork
 * editor only needs the row mapper, so those gallery-wide concerns stay in Aves' own code.
 */
fun <T> Cursor?.mapEachRow(
    projection: Array<String>,
    mapping: (Cursor, Array<Int>) -> T,
) = this?.use { cursor ->
    if (!cursor.moveToFirst()) {
        return@use emptyList<T>()
    }
    val indexCache = projection.map { column ->
        cursor.getColumnIndexOrThrow(column)
    }.toTypedArray()
    buildList {
        do {
            add(mapping(cursor, indexCache))
        } while (cursor.moveToNext())
    }
} ?: emptyList()

fun Cursor?.tryGetString(columnIndex: Int, fallback: String? = null): String? =
    this?.getStringOrNull(columnIndex) ?: fallback

fun Cursor?.tryGetLong(columnIndex: Int, fallback: Long? = null): Long? =
    this?.getLongOrNull(columnIndex) ?: fallback
