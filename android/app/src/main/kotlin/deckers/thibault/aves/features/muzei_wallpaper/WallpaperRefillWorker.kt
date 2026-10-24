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

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.CancellationException

/**
 * Runs one wallpaper refill without the app UI.
 *
 * The actual bake is Dart (`refill_entry.dart`): it already owns sources, EXIF
 * decoding and the blur pipeline, and duplicating it in Kotlin would let the
 * wallpaper and the preview drift apart. This worker only drives the warm
 * headless engine (`WallpaperRefillEngine`) and, for auto-advance, reloads the
 * wallpaper and starts the next countdown.
 */
class WallpaperRefillWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    companion object {
        private const val TAG = "AvesLiveWallpaper"
        const val KEY_ADVANCE = "advance"
    }

    override suspend fun doWork(): Result {
        val advance = inputData.getBoolean(KEY_ADVANCE, true)
        // A tap is already being served by the mounted page over the channel;
        // running the worker too would bake the same slot twice.
        if (!advance && WallpaperAppBridge.isRequestHandlerAttached) {
            Log.d(TAG, "refill.skip: the page is listening")
            return Result.success()
        }
        Log.d(TAG, "refill.start advance=$advance work=$id")
        return try {
            WallpaperRefillEngine.refill(applicationContext, advance)
            Log.d(TAG, "refill.done advance=$advance")
            if (advance) {
                // The renderer reload already ran through the channel; this
                // catches the wallpaper engine being recreated meanwhile.
                WallpaperRenderBus.reload()
                WallpaperAppBridge.notifyStateChanged()
                WallpaperRefillScheduler.rescheduleAutoAdvance(applicationContext)
            }
            Result.success()
        } catch (e: CancellationException) {
            // WorkManager cancelled the run: propagate instead of reporting a
            // result for work that no longer exists.
            throw e
        } catch (t: Throwable) {
            // Retrying a bake that just failed would spin on the same artwork;
            // the next tap or interval starts a fresh run instead.
            Log.w(TAG, "refill.failed advance=$advance", t)
            if (advance) WallpaperRefillScheduler.rescheduleAutoAdvance(applicationContext)
            Result.success()
        }
    }
}
