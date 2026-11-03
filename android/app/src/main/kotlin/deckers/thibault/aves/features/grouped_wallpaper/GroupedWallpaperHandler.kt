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
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import deckers.thibault.aves.channel.calls.Coresult.Companion.safe
import deckers.thibault.aves.channel.calls.Coresult.Companion.safeSuspend
import deckers.thibault.aves.features.live_wallpaper_refill.LiveWallpaperRefillScheduler
import deckers.thibault.aves.features.live_wallpaper_refill.LiveWallpaperTarget
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
 * Lifecycle commands cross it, plus the one write that has to stay native: the
 * frame bake. `state.json` and the frame files are shared, so applying a frame
 * never depends on a channel round trip.
 */
class GroupedWallpaperHandler(
    private val context: Context,
    /**
     * Whether this channel can receive the service's sync requests.
     *
     * The background refill engine mounts the same handler but is never given a
     * messenger, so it must not claim the app's listening flag: the worker would
     * then skip a refill the service is waiting for.
     */
    private val servesSyncRequests: Boolean = true,
) : MethodCallHandler {
    companion object {
        private const val TAG = "AvesGroupedWallpaper"
        const val CHANNEL = "deckers.thibault/aves/grouped_wallpaper"
    }

    private val defaultScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isActive" -> safe(call, result, ::isActive)
            "capability" -> safe(call, result, ::capability)
            "restoreOffer" -> safe(call, result, ::restoreOffer)
            "reload" -> safe(call, result, ::reload)
            "promotePhoto" -> safe(call, result, ::promotePhoto)
            "openChooser" -> safe(call, result, ::openChooser)
            "wallpaperSize" -> safe(call, result, ::wallpaperSize)
            "displayedSlot" -> safe(call, result, ::displayedSlot)
            "lockSurfaceStatus" -> safe(call, result, ::lockSurfaceStatus)
            "stateRoot" -> safe(call, result, ::stateRoot)
            "writeFrame" -> defaultScope.launch { safeSuspend(call, result, ::writeFrame) }
            "setRequestHandler" -> safe(call, result, ::setRequestHandler)
            "scheduleAutoAdvance" -> safe(call, result, ::scheduleAutoAdvance)
            "restartAutoAdvance" -> safe(call, result, ::restartAutoAdvance)
            "refreshNotification" -> safe(call, result, ::refreshNotification)
            "cancelNotification" -> safe(call, result, ::cancelNotification)
            else -> result.notImplemented()
        }
    }

    /**
     * Reports what the device can actually do with this wallpaper, in one call.
     *
     * The app asks this before applying (to warn once on a device that will not
     * pan) and before every bake (to decide how wide the frame should be). The
     * answer therefore has to distinguish "measured as unsupported" from "not
     * measured": a launcher reports its scroll step only after the wallpaper is
     * bound, so an unbound device must not be narrowed.
     */
    private fun capability(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        val manager = WallpaperManager.getInstance(context)
        val ours = GroupedLiveWallpaperService::class.java.name
        // Before API 34 there is no per-surface live wallpaper, so the bound
        // service is the system one (the same rule `isActive` uses).
        val systemOurs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            manager.getWallpaperInfo(WallpaperManager.FLAG_SYSTEM)?.serviceName == ours
        } else {
            manager.wallpaperInfo?.serviceName == ours
        }
        // Android only separates the lock screen's live wallpaper from API 34.
        val lockOurs = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            manager.getWallpaperInfo(WallpaperManager.FLAG_LOCK)?.serviceName == ours
        val host = when {
            systemOurs && lockOurs -> "both"
            systemOurs -> "home"
            lockOurs -> "lock"
            else -> "none"
        }
        val launcher = try {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            val pm = context.packageManager
            // `MATCH_DEFAULT_ONLY` is how the chosen home is resolved, but it
            // requires `CATEGORY_DEFAULT`: a launcher that omits it would answer
            // nothing, and the fixed-wallpaper warning would silently never fire.
            (pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
                ?: pm.resolveActivity(intent, 0))
                ?.activityInfo?.packageName
                // `android` is the disambiguation dialog, not a launcher: taking
                // it would poison both the fixed-wallpaper check and the key the
                // one-time warning is remembered by.
                ?.takeIf { it != "android" }
                ?: ""
        } catch (e: Exception) {
            // A launcher the app cannot see is "unknown", never "fixed wallpaper".
            Log.w(TAG, "failed to resolve the home launcher", e)
            ""
        }
        // The offsets are process-wide, so they have to follow the launcher they
        // were measured on; done before reading them, so a changed launcher
        // answers "not measured" instead of the previous one's verdict.
        if (launcher.isNotEmpty() && GroupedLiveWallpaperService.adoptLauncher(launcher)) {
            Log.d(TAG, "capability offsets reset for launcher=$launcher")
        }
        // MIUI keeps its "scroll the wallpaper with the home pages" switch in
        // Settings.Secure. Other ROMs have no such key, which answers null.
        val span = try {
            Settings.Secure.getString(context.contentResolver, "pref_key_wallpaper_screen_scrolled_span")?.toIntOrNull()
        } catch (e: Exception) {
            Log.w(TAG, "failed to read the wallpaper scroll setting", e)
            null
        }
        val step = GroupedLiveWallpaperService.scrollStep.takeIf { it >= 0.0 }
        result.success(
            mapOf(
                "host" to host,
                "launcher" to launcher,
                "model" to Build.MODEL.orEmpty(),
                "scrollSpan" to span,
                "scrollStep" to step,
                "scrollOffsetMoved" to GroupedLiveWallpaperService.scrollOffsetMoved,
            ),
        )
    }

    private fun isActive(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        val manager = WallpaperManager.getInstance(context)
        val ours = GroupedLiveWallpaperService::class.java.name
        val active = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            manager.getWallpaperInfo(WallpaperManager.FLAG_SYSTEM)?.serviceName == ours ||
                manager.getWallpaperInfo(WallpaperManager.FLAG_LOCK)?.serviceName == ours
        } else {
            manager.wallpaperInfo?.serviceName == ours
        }
        result.success(active)
    }

    /**
     * Whether the system lock screen draws this app's live wallpaper.
     *
     * Android only separates the lock screen's live wallpaper from API 34, so an
     * older device honestly answers `unknown` instead of guessing. The decoy
     * surface is only useful when the answer is `ours`, which is what the page
     * warns about.
     */
    private fun lockSurfaceStatus(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        val status = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            "unknown"
        } else {
            val info = WallpaperManager.getInstance(context).getWallpaperInfo(WallpaperManager.FLAG_LOCK)
            when {
                info == null -> "none"
                info.serviceName == GroupedLiveWallpaperService::class.java.name -> "ours"
                else -> "other"
            }
        }
        result.success(mapOf("status" to status))
    }

    /**
     * Whether the app should offer the wallpaper back.
     *
     * The app asks on every return, because the binding can be lost while it is
     * away; the answer is the same rule the startup restore uses, so the notice
     * never offers a live wallpaper the user picked.
     */
    private fun restoreOffer(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        result.success(GroupedWallpaperRestore.restoreOffer(context))
    }

    private fun reload(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        GroupedWallpaperRenderBus.reload()
        result.success(null)
    }

    /**
     * Promotes the queued neighbour for the in-app view, like a wallpaper tap.
     *
     * The app asks this before falling back to one of its own commands: the
     * renderer already holds the neighbour's texture, so the frame changes in one
     * swap instead of a bake. The promotion writes `runtime.json` synchronously,
     * and the bar is re-posted at once from the slot the renderer now draws; the
     * app refills the freed slot in the background.
     */
    private fun promotePhoto(call: MethodCall, result: MethodChannel.Result) {
        val previous = call.argument<Boolean>("previous") ?: false
        val promoted = if (previous) GroupedWallpaperRenderBus.previous() else GroupedWallpaperRenderBus.advance()
        if (promoted) GroupedLiveWallpaperService.refreshNotification()
        result.success(promoted)
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

    /**
     * Reports the slot the wallpaper engine is actually drawing, or `-1`, plus
     * the surface it draws.
     *
     * `state.json` says what was last baked, which is not always the frame on
     * screen; the app uses this to describe the photo the user can see, with the
     * effect the renderer applied for that surface.
     */
    private fun displayedSlot(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        // A split group draws the decoy on the lock screen: it is not a queue
        // slot, so the app is told which surface it is looking at instead.
        val splitLock = GroupedLiveWallpaperService.lockScreenVisible &&
            GroupedWallpaperStateFile.read(context)?.let { it.lock != null || it.lockRangeId.isNotEmpty() } == true
        result.success(
            mapOf(
                "slot" to if (splitLock) -1 else GroupedLiveWallpaperService.displayedSlot,
                "lock" to GroupedLiveWallpaperService.lockScreenVisible,
                "surface" to if (splitLock) "lock" else "home",
            ),
        )
    }

    private fun stateRoot(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {        result.success(GroupedWallpaperStateFile.ensureRoot(context).absolutePath)
    }

    /**
     * Decodes, covers and writes one wallpaper frame, reporting its size and a
     * darkness sample.
     *
     * `null` means "bake it in Dart", not a failed request: the channel is an
     * optimization, so an undecodable entry or a desktop host simply takes the
     * fallback the engine already has.
     */
    private suspend fun writeFrame(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val mimeType = call.argument<String>("mimeType")
        val outputPath = call.argument<String>("outputPath")
        val targetWidth = call.argument<Int>("targetWidth")
        val targetHeight = call.argument<Int>("targetHeight")
        if (uri == null || mimeType == null || outputPath == null || targetWidth == null || targetHeight == null || targetWidth <= 0 || targetHeight <= 0) {
            result.success(null)
            return
        }
        val written = GroupedFrameWriter.write(
            context,
            GroupedFrameWriter.Request(
                uri = uri,
                mimeType = mimeType,
                pageId = call.argument<Int>("pageId"),
                sizeBytes = call.argument<Number>("sizeBytes")?.toLong(),
                rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0,
                isFlipped = call.argument<Boolean>("isFlipped") == true,
                targetWidth = targetWidth,
                targetHeight = targetHeight,
                outputPath = outputPath,
                quality = call.argument<Int>("quality") ?: GroupedFrameWriter.DEFAULT_QUALITY,
                extraRotationDegrees = call.argument<Int>("extraRotationDegrees") ?: 0,
                fit = call.argument<String>("fit") ?: "fill",
            ),
        )
        result.success(
            written?.let {
                mapOf("width" to it.width, "height" to it.height, "thumbnail" to it.thumbnail)
            },
        )
    }

    /**
     * Records whether the app listens for `syncRequested`.
     *
     * When it does and the service is already the wallpaper, ask for a frame
     * immediately: opening the app after the wallpaper was set is the common way
     * to get the first image.
     */
    private fun setRequestHandler(call: MethodCall, result: MethodChannel.Result) {
        if (!servesSyncRequests) {
            // A headless engine registers the handler too, but the service cannot
            // reach it; leaving the flag untouched keeps the worker's decision
            // honest.
            result.success(null)
            return
        }
        val attached = call.argument<Boolean>("attached") == true
        GroupedWallpaperAppBridge.setRequestHandlerAttached(attached)
        if (attached && GroupedLiveWallpaperService.isRunning) {
            GroupedWallpaperAppBridge.requestSync()
        }
        result.success(null)
    }

    /**
     * Applies the current group's interval to the shared auto-advance scheduler.
     *
     * The scheduler and the worker are shared with Muzei, so the interval is
     * stored per target; `0` cancels the pending run.
     */
    private fun scheduleAutoAdvance(call: MethodCall, result: MethodChannel.Result) {
        val seconds = call.argument<Int>("seconds") ?: 0
        LiveWallpaperRefillScheduler.scheduleAutoAdvance(context, LiveWallpaperTarget.GROUPED, seconds)
        result.success(null)
    }

    /**
     * Restarts the interval after a manual previous/next step.
     *
     * It replaces the pending run instead of keeping it, so the user's step is
     * followed by a full interval rather than an immediate automatic change.
     */
    private fun restartAutoAdvance(call: MethodCall, result: MethodChannel.Result) {
        val seconds = call.argument<Int>("seconds") ?: 0
        LiveWallpaperRefillScheduler.restartAutoAdvance(context, LiveWallpaperTarget.GROUPED, seconds)
        result.success(null)
    }

    /**
     * Re-posts or drops the bar from the state the app just wrote.
     *
     * Turning the notification off has to take effect without waiting for the next
     * frame: the app rewrites `state.json` with the new flag, then asks the running
     * service to read it again.
     */
    private fun refreshNotification(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        GroupedLiveWallpaperService.refreshNotification()
        result.success(null)
    }

    /**
     * Drops a bar left behind by a service that never ran `onDestroy`.
     *
     * The app calls this when it attaches the engine and finds the grouped
     * wallpaper is no longer the system wallpaper, so a killed service cannot
     * leave its notification in the shade until the next boot.
     */
    private fun cancelNotification(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        GroupedLiveWallpaperService.cancelNotification(context)
        result.success(null)
    }
}
