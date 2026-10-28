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

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge from the wallpaper service back to the running app.
 *
 * The service asks for a frame when it starts or when the app attaches, which is
 * how the wallpaper gets its first photo: there is no background worker in this
 * phase, so without a listening app the renderer keeps its placeholder until the
 * app is opened.
 */
object GroupedWallpaperAppBridge {
    private const val TAG = "AvesGroupedWallpaper"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var messenger: BinaryMessenger? = null

    /** Whether the app engine currently listens for `syncRequested`. */
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

    /** Whether a mounted app engine currently listens for `syncRequested`. */
    val isRequestHandlerAttached: Boolean
        get() = requestHandlerAttached

    /** Asks the app to bake a frame now; false when no app is listening. */
    fun requestSync(): Boolean {
        val engineMessenger = messenger ?: return false
        if (!requestHandlerAttached) return false
        mainHandler.post {
            try {
                MethodChannel(engineMessenger, GroupedWallpaperHandler.CHANNEL)
                    .invokeMethod("syncRequested", null)
            } catch (t: Throwable) {
                Log.w(TAG, "failed to ask the app for a frame", t)
            }
        }
        return true
    }
}
