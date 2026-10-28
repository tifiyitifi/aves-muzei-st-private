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
 * Method channel between the Flutter engine and the grouped wallpaper service.
 *
 * Only lifecycle commands cross it: the baked photo and `state.json` are shared
 * files, so applying a frame never depends on a channel round trip.
 */
class GroupedWallpaperHandler(private val context: Context) : MethodCallHandler {
    companion object {
        private const val TAG = "AvesGroupedWallpaper"
        const val CHANNEL = "deckers.thibault/aves/grouped_wallpaper"
    }

    private val defaultScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isActive" -> safe(call, result, ::isActive)
            "reload" -> safe(call, result, ::reload)
            "openChooser" -> safe(call, result, ::openChooser)
            "wallpaperSize" -> safe(call, result, ::wallpaperSize)
            "stateRoot" -> safe(call, result, ::stateRoot)
            "setRequestHandler" -> safe(call, result, ::setRequestHandler)
            else -> result.notImplemented()
        }
    }

    private fun isActive(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        val info = WallpaperManager.getInstance(context).wallpaperInfo
        result.success(info?.serviceName == GroupedLiveWallpaperService::class.java.name)
    }

    private fun reload(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        GroupedWallpaperRenderBus.reload()
        result.success(null)
    }

    private fun openChooser(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        defaultScope.launch {
            try {
                // The generic chooser is the reliable entry point on OEM builds
                // that close the per-component preview immediately (observed on
                // MIUI); the direct intent stays as a shortcut.
                val chooser = Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (start(chooser)) {
                    result.success(true)
                    return@launch
                }

                val component = ComponentName(context, GroupedLiveWallpaperService::class.java)
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
        result.success(GroupedWallpaperStateFile.ensureRoot(context).absolutePath)
    }

    /**
     * Records whether the app listens for `syncRequested`.
     *
     * When it does and the service is already the wallpaper, ask for a frame
     * immediately: opening the app after the wallpaper was set is the common way
     * to get the first image.
     */
    private fun setRequestHandler(call: MethodCall, result: MethodChannel.Result) {
        val attached = call.argument<Boolean>("attached") == true
        GroupedWallpaperAppBridge.setRequestHandlerAttached(attached)
        if (attached && GroupedLiveWallpaperService.isRunning) {
            GroupedWallpaperAppBridge.requestSync(null)
        }
        result.success(null)
    }
}
