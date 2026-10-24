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

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge from the wallpaper service back to the running app.
 *
 * The wallpaper can be tapped while Aves is in the background: the renderer
 * promotes the prefetched slot, then asks the app to adopt it and bake the next
 * one. Without a running app there is no receiver; the runtime stays marked for
 * refill and the app adopts it the next time it starts.
 */
object WallpaperAppBridge {
    private const val TAG = "AvesLiveWallpaper"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var messenger: BinaryMessenger? = null

    fun attach(engineMessenger: BinaryMessenger) {
        messenger = engineMessenger
    }

    fun detach(engineMessenger: BinaryMessenger) {
        if (messenger === engineMessenger) {
            messenger = null
        }
    }

    /** Asks the app to adopt the slot the renderer advanced to and refill it. */
    fun notifyAdvanced() {
        val engineMessenger = messenger
        if (engineMessenger == null) {
            Log.d(TAG, "advance notification skipped: the app is not running")
            return
        }
        mainHandler.post {
            try {
                MethodChannel(engineMessenger, LiveWallpaperHandler.CHANNEL)
                    .invokeMethod("advanceRequested", null)
            } catch (t: Throwable) {
                Log.w(TAG, "failed to notify the app of the advance", t)
            }
        }
    }
}
