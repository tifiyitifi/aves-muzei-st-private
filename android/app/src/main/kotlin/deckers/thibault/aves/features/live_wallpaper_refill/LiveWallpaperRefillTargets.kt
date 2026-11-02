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
import android.os.PowerManager
import android.util.Log
import androidx.work.ListenableWorker
import deckers.thibault.aves.features.grouped_wallpaper.GroupedLiveWallpaperService
import deckers.thibault.aves.features.grouped_wallpaper.GroupedWallpaperAppBridge
import deckers.thibault.aves.features.grouped_wallpaper.GroupedWallpaperRenderBus
import deckers.thibault.aves.features.muzei_wallpaper.WallpaperAppBridge
import deckers.thibault.aves.features.muzei_wallpaper.WallpaperRenderBus
import kotlinx.coroutines.CancellationException

/**
 * The one place that knows both live wallpapers.
 *
 * The shared worker and engine stay target-agnostic; this object is the
 * composition root that maps a target onto the feature that owns it. Adding a
 * third wallpaper means adding a branch here, not another scheduler.
 */
object LiveWallpaperRefillTargets {
    private const val TAG = "AvesLiveWallpaper"

    /**
     * Runs one refill for [target].
     *
     * A tap is already being served by the mounted page over the channel;
     * running the worker too would bake the same slot twice. Auto-advance always
     * runs, because the page does not own the interval.
     */
    suspend fun run(context: Context, target: LiveWallpaperTarget, advance: Boolean, command: String? = null): ListenableWorker.Result {
        // A command must run even when the page is mounted: the page does not
        // own group switching or freezing, and a tap is already being served by
        // the mounted engine over the channel.
        if (!advance && command == null && isAppListening(target)) {
            Log.d(TAG, "refill.skip target=${target.id}: the page is listening")
            return ListenableWorker.Result.success()
        }
        // A timed advance is only baked when its surface can actually be seen.
        // Behind a video, or with the screen off, the bake would be invisible
        // work; the advance is remembered and applied on the next show instead.
        if (advance && command == null && target == LiveWallpaperTarget.GROUPED && !canBakeNow(context)) {
            Log.d(TAG, "refill.defer target=${target.id}: the wallpaper is not visible")
            LiveWallpaperRefillScheduler.markPendingAdvance(context, target)
            LiveWallpaperRefillScheduler.rescheduleAutoAdvance(context, target)
            return ListenableWorker.Result.success()
        }
        Log.d(TAG, "refill.start target=${target.id} advance=$advance command=$command")
        return try {
            LiveWallpaperRefillEngine.refill(context, target, advance, command)
            Log.d(TAG, "refill.done target=${target.id} advance=$advance command=$command")
            onRefilled(context, target, advance)
            ListenableWorker.Result.success()
        } catch (e: CancellationException) {
            // WorkManager cancelled the run: propagate instead of reporting a
            // result for work that no longer exists.
            throw e
        } catch (t: Throwable) {
            // Retrying a bake that just failed would spin on the same artwork;
            // the next tap or interval starts a fresh run instead.
            Log.w(TAG, "refill.failed target=${target.id} advance=$advance command=$command", t)
            if (advance) LiveWallpaperRefillScheduler.rescheduleAutoAdvance(context, target)
            ListenableWorker.Result.success()
        }
    }

    /** Whether a bake would be seen: interactive screen and a visible surface. */
    private fun canBakeNow(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!power.isInteractive) return false
        return GroupedLiveWallpaperService.wallpaperVisible
    }

    /** Whether a mounted page serves this target's refill requests. */
    fun isAppListening(target: LiveWallpaperTarget): Boolean = when (target) {
        LiveWallpaperTarget.MUZEI -> WallpaperAppBridge.isRequestHandlerAttached
        // The service and the worker must use the same predicate, or a request
        // can be refused by one and skipped by the other.
        LiveWallpaperTarget.GROUPED -> GroupedWallpaperAppBridge.canServeRequests
    }

    /**
     * Applies a finished run to the wallpaper that is on screen.
     *
     * The renderer reload catches an engine that was recreated while the bake
     * ran; auto-advance then starts the next countdown, because the finished run
     * still owns the unique work name.
     */
    private fun onRefilled(context: Context, target: LiveWallpaperTarget, advance: Boolean) {
        when (target) {
            LiveWallpaperTarget.MUZEI -> {
                WallpaperRenderBus.reload()
                WallpaperAppBridge.notifyStateChanged()
            }

            LiveWallpaperTarget.GROUPED -> GroupedWallpaperRenderBus.reload()
        }
        if (advance) LiveWallpaperRefillScheduler.rescheduleAutoAdvance(context, target)
    }
}
