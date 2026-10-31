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

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import deckers.thibault.aves.MainActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge from the wallpaper service back to the running app.
 *
 * The service asks for a frame when it starts, after a promoted slot, and when the
 * app attaches, which is how the wallpaper gets its first photo and how a tap
 * refills the queue. A gesture that opens a page has no Activity of its own, so
 * it starts the app like Muzei does.
 */
object GroupedWallpaperAppBridge {
    private const val TAG = "AvesGroupedWallpaper"

    /** The app route of the immersive wallpaper view. */
    private const val GroupedWallpaperViewRoute = "/grouped_wallpaper/view"

    /** The app route of the wallpaper group page. */
    private const val GroupedWallpaperPageRoute = "/wallpaper_groups"

    /** The app route of the group page that asks for the PIN at once. */
    private const val GroupedWallpaperUnlockRoute = "/wallpaper_groups/unlock"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var context: Context? = null

    @Volatile
    private var messenger: BinaryMessenger? = null

    /** Whether the app engine currently listens for `syncRequested`. */
    @Volatile
    private var requestHandlerAttached = false

    fun attach(engineMessenger: BinaryMessenger) {
        messenger = engineMessenger
    }

    /** Keeps the application context so a gesture can start the app. */
    fun attachContext(appContext: Context) {
        context = appContext.applicationContext
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

    /**
     * Asks the app to bake a frame now; false when no app is listening.
     *
     * The promotion is not passed along: the renderer already wrote
     * `runtime.json` synchronously before asking, so the app reads the same
     * record whether it was notified or is picking the work up later.
     */
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

    /**
     * Asks the app to run a notification command (previous photo, group switch,
     * freeze); false when no app is listening.
     *
     * The app owns every change that needs a bake or a database write, so the
     * receiver routes through it before falling back to the background worker.
     */
    fun requestCommand(command: String): Boolean {
        val engineMessenger = messenger ?: return false
        if (!requestHandlerAttached) return false
        mainHandler.post {
            try {
                MethodChannel(engineMessenger, GroupedWallpaperHandler.CHANNEL)
                    .invokeMethod("command", mapOf("command" to command))
            } catch (t: Throwable) {
                Log.w(TAG, "failed to send the wallpaper command $command", t)
            }
        }
        return true
    }

    /**
     * Opens the grouped wallpaper's view page.
     *
     * A wallpaper gesture has no Activity, so this starts the app (cold start is
     * expected, exactly like Muzei's artwork gesture). The page is a normal route
     * of the app, so it is the same page the group page's menu opens.
     */
    fun requestView() {
        requestPage(GroupedWallpaperViewRoute)
    }

    /** Opens the wallpaper group page, which is also the notification's target. */
    fun requestGroupPage() {
        requestPage(GroupedWallpaperPageRoute)
    }

    /**
     * Opens the wallpaper group page and asks for the PIN.
     *
     * The lock button is the way into the lock, so tapping it while locked is the
     * user asking to unlock: the page prompts instead of waiting for the menu.
     */
    fun requestGroupUnlock() {
        requestPage(GroupedWallpaperUnlockRoute)
    }

    private fun requestPage(route: String) {
        val appContext = context ?: return
        try {
            appContext.startActivity(
                Intent(appContext, MainActivity::class.java)
                    .setAction(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_LAUNCHER)
                    .putExtra("page", route)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "failed to open the grouped wallpaper page $route", t)
        }
    }
}
