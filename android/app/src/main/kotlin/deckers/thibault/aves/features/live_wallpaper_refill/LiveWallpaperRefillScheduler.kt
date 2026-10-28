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
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

/**
 * Schedules the headless refill runs of both live wallpapers.
 *
 * Both bake in Dart, so without a worker a tap or an interval would only be
 * served while the app process is alive. WorkManager (not an alarm) because the
 * work is deferrable and must survive reboots; auto-advance is a chain of
 * one-time runs instead of periodic work so long intervals stay exact.
 *
 * Every entry point takes a [LiveWallpaperTarget], so one scheduler keeps the two
 * wallpapers apart: unique work names, callback prefs and intervals are per
 * target, and only the engine boot is shared.
 */
object LiveWallpaperRefillScheduler {
    private const val TAG = "AvesLiveWallpaper"

    /** The channel the app registers the callback on and the worker boots. */
    const val CHANNEL = "deckers.thibault/aves/live_wallpaper_refill"

    /** Shared with [LiveWallpaperRefillWorker] and `FlutterUtils.initFlutterEngine`. */
    const val SHARED_PREFERENCES_KEY = "live_wallpaper_refill_service"
    const val PREF_CALLBACK_HANDLE_KEY = "callback_handle"

    private const val PREF_AUTO_INTERVAL_PREFIX = "auto_interval_seconds_"

    private fun tapWorkName(target: LiveWallpaperTarget) = "live_wallpaper_${target.id}_tap_refill"

    private fun autoWorkName(target: LiveWallpaperTarget) = "live_wallpaper_${target.id}_auto_advance"

    private fun commandWorkName(target: LiveWallpaperTarget) = "live_wallpaper_${target.id}_command"

    private fun intervalKey(target: LiveWallpaperTarget) = "$PREF_AUTO_INTERVAL_PREFIX${target.id}"

    /** Persists the `vm:entry-point` callback handle the worker boots. */
    fun registerCallback(context: Context, callbackHandle: Long) {
        context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
            .edit()
            .putLong(PREF_CALLBACK_HANDLE_KEY, callbackHandle)
            .apply()
        Log.d(TAG, "refill.callback registered=${callbackHandle != 0L}")
    }

    /**
     * Starts one refill after a wallpaper tap that no running app could serve.
     *
     * `APPEND_OR_REPLACE` serializes bursts: a second tap waits for the running
     * bake instead of cancelling it, because the renderer replays its buffered
     * taps one per refill. [ensure] is used by the recovery path (a tap found no
     * prefetched slot), where a single pending run is enough and `KEEP` avoids
     * stacking one work per tap.
     *
     * Deliberately not expedited: on Android 12+ that runs the work as a
     * foreground service, which requires `getForegroundInfo()` and a
     * notification for a two-second bake. The user just tapped the wallpaper, so
     * a plain job still runs right away.
     */
    fun enqueueTapRefill(context: Context, target: LiveWallpaperTarget, ensure: Boolean = false) {
        val request = OneTimeWorkRequestBuilder<LiveWallpaperRefillWorker>()
            .setInputData(
                workDataOf(
                    LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                    LiveWallpaperRefillWorker.KEY_ADVANCE to false,
                ),
            )
            .build()
        val policy = if (ensure) ExistingWorkPolicy.KEEP else ExistingWorkPolicy.APPEND_OR_REPLACE
        WorkManager.getInstance(context).enqueueUniqueWork(tapWorkName(target), policy, request)
        Log.d(TAG, "refill.enqueue target=${target.id} ensure=$ensure")
    }

    /**
     * Runs a notification command even when no app is alive.
     *
     * Commands change the saved group or the freeze flag, so they are queued
     * (`APPEND_OR_REPLACE`) instead of replaced: "next group" followed by "freeze"
     * must keep that order.
     */
    fun enqueueCommand(context: Context, target: LiveWallpaperTarget, command: String) {
        val request = OneTimeWorkRequestBuilder<LiveWallpaperRefillWorker>()
            .setInputData(
                workDataOf(
                    LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                    LiveWallpaperRefillWorker.KEY_ADVANCE to false,
                    LiveWallpaperRefillWorker.KEY_COMMAND to command,
                ),
            )
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(commandWorkName(target), ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        Log.d(TAG, "refill.command target=${target.id} command=$command")
    }

    /**
     * Applies the interval chosen in the app; `0` disables auto-advance.
     *
     * Reopening the page must not restart the countdown, so an unchanged
     * interval keeps the pending run (`KEEP`) while a changed one replaces it.
     */
    fun scheduleAutoAdvance(context: Context, target: LiveWallpaperTarget, seconds: Int) {
        val prefs = context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        val key = intervalKey(target)
        val previous = prefs.getInt(key, 0)
        val manager = WorkManager.getInstance(context)
        if (seconds <= 0) {
            prefs.edit().putInt(key, 0).apply()
            manager.cancelUniqueWork(autoWorkName(target))
            Log.d(TAG, "auto.schedule target=${target.id} off")
            return
        }
        prefs.edit().putInt(key, seconds).apply()
        val request = OneTimeWorkRequestBuilder<LiveWallpaperRefillWorker>()
            .setInputData(
                workDataOf(
                    LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                    LiveWallpaperRefillWorker.KEY_ADVANCE to true,
                ),
            )
            .setInitialDelay(seconds.toLong(), TimeUnit.SECONDS)
            .build()
        val policy = if (previous == seconds) ExistingWorkPolicy.KEEP else ExistingWorkPolicy.REPLACE
        manager.enqueueUniqueWork(autoWorkName(target), policy, request)
        Log.d(TAG, "auto.schedule target=${target.id} seconds=$seconds previous=$previous")
    }

    /**
     * Starts the next countdown after a run.
     *
     * The finished run still owns the unique name, so this appends rather than
     * inserts; `KEEP` would see the running work and drop the next interval.
     */
    fun rescheduleAutoAdvance(context: Context, target: LiveWallpaperTarget) {
        val seconds = autoAdvanceInterval(context, target)
        if (seconds <= 0) return
        val request = OneTimeWorkRequestBuilder<LiveWallpaperRefillWorker>()
            .setInputData(
                workDataOf(
                    LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                    LiveWallpaperRefillWorker.KEY_ADVANCE to true,
                ),
            )
            .setInitialDelay(seconds.toLong(), TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(autoWorkName(target), ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        Log.d(TAG, "auto.reschedule target=${target.id} seconds=$seconds")
    }

    /** The interval currently scheduled for [target], or 0 when it is off. */
    fun autoAdvanceInterval(context: Context, target: LiveWallpaperTarget): Int =
        context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
            .getInt(intervalKey(target), 0)
}
