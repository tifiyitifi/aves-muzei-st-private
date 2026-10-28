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

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/**
 * One background refill for one live wallpaper.
 *
 * The bake is Dart (`live_wallpaper_refill/refill_entry.dart`): sources, EXIF
 * decoding and the effect pipelines already live there, and duplicating them in
 * Kotlin would let a wallpaper and its preview drift apart. This worker only
 * drives the warm headless engine and hands the result back to the target.
 */
class LiveWallpaperRefillWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    companion object {
        const val KEY_TARGET = "target"
        const val KEY_ADVANCE = "advance"
        const val KEY_COMMAND = "command"
    }

    override suspend fun doWork(): Result {
        val target = LiveWallpaperTarget.fromId(inputData.getString(KEY_TARGET))
        val advance = inputData.getBoolean(KEY_ADVANCE, true)
        val command = inputData.getString(KEY_COMMAND)
        return LiveWallpaperRefillTargets.run(applicationContext, target, advance, command)
    }
}
