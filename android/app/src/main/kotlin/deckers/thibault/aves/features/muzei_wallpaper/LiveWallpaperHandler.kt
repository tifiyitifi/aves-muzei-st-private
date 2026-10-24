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

import android.app.WallpaperManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import deckers.thibault.aves.channel.calls.Coresult.Companion.safe
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Method channel between the Flutter wallpaper page and the native service.
 *
 * Baked files are never sent over the channel: both sides read the same
 * `state.json`, and this handler only carries lifecycle commands. Ported from
 * Muzei's `MuzeiWallpaperService` / settings intents (Apache-2.0).
 */
class LiveWallpaperHandler(private val context: Context) : MethodCallHandler {
    companion object {
        private const val TAG = "AvesLiveWallpaper"
        const val CHANNEL = "deckers.thibault/aves/muzei_wallpaper"
    }

    private val defaultScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isActive" -> safe(call, result, ::isActive)
            "reload" -> safe(call, result, ::reload)
            "openChooser" -> safe(call, result, ::openChooser)
            "wallpaperSize" -> safe(call, result, ::wallpaperSize)
            "stateRoot" -> safe(call, result, ::stateRoot)
            "registerCallback" -> safe(call, result, ::registerCallback)
            "scheduleAutoAdvance" -> safe(call, result, ::scheduleAutoAdvance)
            "setRequestHandler" -> safe(call, result, ::setRequestHandler)
            else -> result.notImplemented()
        }
    }

    private fun isActive(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        val info = WallpaperManager.getInstance(context).wallpaperInfo
        result.success(info?.serviceName == AvesLiveWallpaperService::class.java.name)
    }

    private fun reload(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        WallpaperRenderBus.reload()
        result.success(null)
    }

    private fun openChooser(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        defaultScope.launch {
            try {
                // The per-component preview activity closes immediately on some
                // OEM builds (observed on MIUI), leaving the user with no visible
                // response. The generic chooser is one extra tap but reliable, so
                // it is the primary entry point; the direct intent stays as a
                // shortcut for devices that handle it correctly.
                val chooser = Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (start(chooser)) {
                    result.success(true)
                    return@launch
                }

                val component = ComponentName(context, AvesLiveWallpaperService::class.java)
                val direct = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
                    .putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (start(direct)) {
                    result.success(true)
                    return@launch
                }

                val picker = Intent(Intent.ACTION_SET_WALLPAPER)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (start(picker)) {
                    result.success(true)
                    return@launch
                }

                result.success(false)
            } catch (e: Exception) {
                Log.w(TAG, "failed to open the wallpaper chooser", e)
                result.error("openChooser-exception", e.message, e.stackTraceToString())
            }
        }
    }

    private fun start(intent: Intent): Boolean = try {
        context.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        Log.w(TAG, "wallpaper intent unavailable action=${intent.action}")
        false
    } catch (e: SecurityException) {
        Log.w(TAG, "wallpaper intent denied action=${intent.action}", e)
        false
    }

    private fun wallpaperSize(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        val manager = WallpaperManager.getInstance(context)
        var width = manager.desiredMinimumWidth
        var height = manager.desiredMinimumHeight
        if (width <= 0 || height <= 0) {
            val metrics = context.resources.displayMetrics
            width = metrics.widthPixels
            height = metrics.heightPixels
        }
        result.success(mapOf("width" to width, "height" to height))
    }

    private fun stateRoot(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        val directory = WallpaperStateStore.forContext(context).ensureRoot()
        result.success(directory.absolutePath)
    }

    /**
     * Stores the callback handle of the headless refill entrypoint.
     *
     * Persisted in native preferences because the worker needs it before any
     * Flutter isolate exists.
     */
    private fun registerCallback(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<Number>("callbackHandle")?.toLong() ?: 0L
        WallpaperRefillScheduler.registerCallback(context, handle)
        result.success(handle > 0L)
    }

    /** Applies the auto-advance interval; `0` cancels the pending run. */
    private fun scheduleAutoAdvance(call: MethodCall, result: MethodChannel.Result) {
        val seconds = call.argument<Number>("seconds")?.toInt() ?: 0
        WallpaperRefillScheduler.scheduleAutoAdvance(context, seconds)
        result.success(null)
    }

    /**
     * Records whether a page currently listens for native requests.
     *
     * Without a listener the renderer must route a tap to the background
     * worker, even though the app engine may still be alive on another page.
     */
    private fun setRequestHandler(call: MethodCall, result: MethodChannel.Result) {
        WallpaperAppBridge.setRequestHandlerAttached(call.argument<Boolean>("attached") == true)
        result.success(null)
    }
}
