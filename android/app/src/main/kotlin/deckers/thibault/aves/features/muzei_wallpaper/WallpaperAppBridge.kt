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
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge from the wallpaper service back to the running app, or to the
 * background refill when there is no app.
 *
 * The wallpaper can be tapped while Aves is in the background: the renderer
 * promotes the prefetched slot, then asks someone to adopt it and bake the next
 * one. A running app does that over the channel; otherwise a WorkManager run
 * boots a short-lived Flutter engine, so repeated taps keep advancing instead of
 * stopping after the one prefetched artwork.
 */
object WallpaperAppBridge {
    private const val TAG = "AvesLiveWallpaper"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var messenger: BinaryMessenger? = null

    /** Whether a mounted page listens for `advanceRequested`. */
    @Volatile
    private var requestHandlerAttached = false

    fun attach(engineMessenger: BinaryMessenger) {
        messenger = engineMessenger
    }

    fun detach(engineMessenger: BinaryMessenger) {
        if (messenger === engineMessenger) {
            messenger = null
            requestHandlerAttached = false
        }
    }

    fun setRequestHandlerAttached(attached: Boolean) {
        requestHandlerAttached = attached
        Log.d(TAG, "app.handler attached=$attached")
    }

    val isRequestHandlerAttached: Boolean
        get() = requestHandlerAttached

    /** Asks for the slot the renderer advanced to to be adopted and refilled. */
    fun notifyAdvanced(context: Context) {
        if (post("advanceRequested")) return
        Log.d(TAG, "advance notification: no listening page, using the background refill")
        WallpaperRefillScheduler.enqueueTapRefill(context)
    }

    /**
     * Recovers a tap that found no prefetched slot.
     *
     * Nothing was promoted, so [notifyAdvanced] never runs and the buffered tap
     * would expire. A listening page is already baking the slot; only the
     * headless path needs a nudge, and one pending run may serve several taps.
     */
    fun requestMissingSlot(context: Context) {
        if (requestHandlerAttached) return
        Log.d(TAG, "advance has no slot to promote, requesting a refill")
        WallpaperRefillScheduler.enqueueTapRefill(context, ensure = true)
    }

    /**
     * Tells a running page that the state changed outside of it.
     *
     * Auto-advance runs in the background worker even when the app is open, so
     * the preview would otherwise keep showing the previous artwork until the
     * app is resumed.
     */
    fun notifyStateChanged() {
        if (!post("advanceRequested")) {
            Log.d(TAG, "state notification skipped: no listening page")
        }
    }

    /** Posts [method] to the app engine; false when no page listens. */
    private fun post(method: String): Boolean {
        val engineMessenger = messenger ?: return false
        if (!requestHandlerAttached) return false
        mainHandler.post {
            try {
                MethodChannel(engineMessenger, LiveWallpaperHandler.CHANNEL)
                    .invokeMethod(method, null)
            } catch (t: Throwable) {
                Log.w(TAG, "failed to notify the app ($method)", t)
            }
        }
        return true
    }
}
