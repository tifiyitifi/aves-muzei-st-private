/*
 * Copyright 2026 Aves contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package deckers.thibault.aves.features.muzei_wallpaper

import org.json.JSONObject

/**
 * Native-owned `runtime.json`.
 *
 * The renderer writes the slot it is actually showing, so the Flutter side can
 * adopt a local advance after the app resumes. A generation mismatch means the
 * file predates the latest `state.json` and must be ignored.
 */
data class WallpaperRuntime(
    val generation: Int,
    val current: Int,
    val next: Int,
    val refillRequested: Boolean = false,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("generation", generation)
        put("current", current)
        put("next", next)
        put("refillRequested", refillRequested)
    }

    companion object {
        val empty = WallpaperRuntime(generation = -1, current = -1, next = -1)

        fun fromJson(json: JSONObject): WallpaperRuntime? {
            if (!json.has("generation")) return null
            return WallpaperRuntime(
                generation = json.optInt("generation", -1),
                current = json.optInt("current", -1),
                next = json.optInt("next", -1),
                refillRequested = json.optBoolean("refillRequested", false),
            )
        }
    }
}
