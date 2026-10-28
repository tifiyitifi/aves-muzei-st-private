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

package deckers.thibault.aves.features.live_wallpaper_refill

/**
 * The live wallpapers that share the background refill pipeline.
 *
 * Both wallpapers bake in Dart and both can advance while the app is gone, so
 * they share one headless entrypoint, one callback handle and one warm engine.
 * The target is what tells the shared run which wallpaper it is serving: the
 * baked files, the renderer to reload and the auto-advance interval stay
 * separate.
 */
enum class LiveWallpaperTarget(val id: String) {
    MUZEI("muzei"),
    GROUPED("grouped");

    companion object {
        /** Unknown ids fall back to Muzei so an old work request still runs. */
        fun fromId(value: String?): LiveWallpaperTarget = entries.firstOrNull { it.id == value } ?: MUZEI
    }
}
