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

package deckers.thibault.aves.features.grouped_wallpaper

/**
 * Decides which uploaded frames a reload has to drop.
 *
 * Muzei keeps its current picture set until the next one has finished loading
 * (`MuzeiBlurRenderer.setAndConsumeImageLoader`), and the same rule applies here:
 * a reload only replaces what the new state no longer names. Judging a frame
 * stale because *this* reload did not decode it is what blanked the wallpaper,
 * since the loader deliberately skips the frames it already uploaded.
 */
object GroupedTextureRetention {
    /**
     * @param uploaded slot id to the `(entryId, photo)` currently on the GPU
     * @param desired slot id to the `(entryId, photo)` the new state draws
     * @param protected slot ids that must survive whatever the state says
     */
    fun staleIds(
        uploaded: Map<Int, Pair<Int, String>>,
        desired: Map<Int, Pair<Int, String>>,
        protected: Set<Int>,
    ): Set<Int> = uploaded.keys.filter { id -> id !in protected && desired[id] != uploaded[id] }.toSet()
}
