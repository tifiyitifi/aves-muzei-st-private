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
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.GLUtils
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import deckers.thibault.aves.MainActivity
import deckers.thibault.aves.R
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.max
import kotlin.math.min

/**
 * State-driven wallpaper renderer.
 *
 * Adapted from Muzei's `render/MuzeiBlurRenderer.kt` and `GLPictureSet`
 * (https://github.com/muzei/muzei, Apache-2.0): the sharp/effect crossfade,
 * temporary focus, cover-fit crop and desktop parallax follow the original.
 *
 * The Flutter side bakes `slots/<id>/sharp.png` plus one effect image per
 * surface; this renderer uploads the sharp texture and the effect texture of
 * the surface being drawn, then crossfades between artworks when the state
 * changes. Everything expensive (file reads, PNG decodes) stays off the GL
 * thread.
 *
 * It also owns the two things that must work while Flutter is not running:
 * temporary focus and promoting the prefetched slot on a wallpaper tap. The
 * promotion is recorded in `runtime.json`, which then wins over `state.json`
 * until Flutter adopts it.
 */
class WallpaperRenderer(
    private val context: Context,
    private val requestRender: () -> Unit,
) : GLSurfaceView.Renderer {
    companion object {
        private const val TAG = "AvesLiveWallpaper"

        /** Muzei crossfades artwork changes over 750 ms. */
        private const val CROSSFADE_MS = 750f

        /** Temporary focus fades the effect image out and back in. */
        private const val FOCUS_MS = 500f

        /** Muzei keeps the sharp artwork visible for three seconds. */
        private const val TEMPORARY_FOCUS_MS = 3000L

        // Gesture action names, matching `WallpaperTapAction` on the Dart side.
        private const val ACTION_TEMPORARY_DISABLE = "temporaryDisable"
        private const val ACTION_NEXT_ARTWORK = "nextArtwork"
        private const val ACTION_VIEW_ARTWORK = "viewArtwork"

        private const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = aTexCoord;
            }
        """

        private const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform sampler2D uTexture;
            uniform float uAlpha;
            varying vec2 vTexCoord;
            void main() {
                vec4 color = texture2D(uTexture, vTexCoord);
                gl_FragColor = vec4(color.rgb, color.a * uAlpha);
            }
        """
    }

    private val store = WallpaperStateStore.forContext(context)

    /** Disk reads and PNG decodes never run on the GL thread. */
    private val loader = Executors.newSingleThreadExecutor()

    private val reloadInFlight = AtomicBoolean(false)
    private val reloadAgain = AtomicBoolean(false)
    private val advanceInFlight = AtomicBoolean(false)

    /**
     * Taps that arrived while no slot was baked yet.
     *
     * Only the loader thread touches the queue, but taps are recorded from the
     * main thread, so every access is synchronized.
     */
    private val advanceRequests = AdvanceRequestQueue()

    private val handler = Handler(Looper.getMainLooper())

    /** Re-applies the effects after a temporary focus. */
    private val restoreFocusTask = Runnable { setFocused(false) }

    @Volatile
    private var doubleTapBinding = ACTION_TEMPORARY_DISABLE

    @Volatile
    private var threeFingerBinding = "none"

    @Volatile
    private var destroyed = false

    /** Decoded by [loader], uploaded by the GL thread. */
    @Volatile
    private var pending: LoadedFrame? = null

    /** The immediate flag captured with the load that produced [pending]. */
    @Volatile
    private var immediateNextLoad = false

    /** Identity of the newest frame accepted by the GL thread. */
    @Volatile
    private var targetIdentity: String? = null

    /** The lock screen is drawn; the effect image of that surface applies. */
    @Volatile
    private var lockScreenVisible = false

    /** Desktop page offset in `0..1`; 0.5 centers the artwork. */
    @Volatile
    private var normalOffsetX = 0.5f

    /** Launcher zoom in `0..1`, where 1 is fully zoomed out. */
    @Volatile
    private var zoom = 1f

    /** Temporary focus: drop the effect image and show the sharp artwork. */
    @Volatile
    private var focused = false

    /** The frame fully drawn on screen (or the placeholder spike). */
    private var current: UploadedFrame? = null

    /** The frame being faded in. */
    private var incoming: UploadedFrame? = null

    /** A newer frame that arrived while a crossfade was running. */
    private var queued: UploadedFrame? = null

    private var crossfadeStartNs = 0L
    private var effectsAlpha = 1f
    private var lastFrameNs = 0L

    private var program = 0
    private var aPosition = -1
    private var aTexCoord = -1
    private var uTexture = -1
    private var uAlpha = -1

    private var viewWidth = 1
    private var viewHeight = 1

    private val vertexBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(4 * 2 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
            position(0)
        }

    private val texCoordBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(4 * 2 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()

    private val texCoords = FloatArray(8)

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        Log.d(TAG, "surface.created")
        destroyed = false
        // A new EGL context invalidates every texture id from the previous one,
        // so drop the frames instead of deleting ids that may now belong to the
        // new context.
        current = null
        incoming = null
        queued = null
        targetIdentity = null
        crossfadeStartNs = 0L
        lastFrameNs = 0L
        try {
            program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            aPosition = GLES20.glGetAttribLocation(program, "aPosition")
            aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
            uTexture = GLES20.glGetUniformLocation(program, "uTexture")
            uAlpha = GLES20.glGetUniformLocation(program, "uAlpha")
            GLES20.glDisable(GLES20.GL_DEPTH_TEST)
            GLES20.glEnable(GLES20.GL_BLEND)
            GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
            GLES20.glClearColor(0.05f, 0.06f, 0.08f, 1f)
            // The spike keeps the surface busy until the first state loads.
            loadSpikeTexture()
            WallpaperRenderBus.attach(this)
            requestReload()
        } catch (t: Throwable) {
            Log.e(TAG, "renderer init failed, falling back to solid color", t)
            program = 0
            current = null
        }
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        Log.d(TAG, "surface.changed w=$width h=$height")
        viewWidth = width.coerceAtLeast(1)
        viewHeight = height.coerceAtLeast(1)
        GLES20.glViewport(0, 0, viewWidth, viewHeight)
        requestRender()
    }

    override fun onDrawFrame(gl: GL10?) {
        consumePending()

        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        if (program == 0) {
            return
        }

        val animating = tickEffectsAlpha() or tickCrossfade() or drawFrames()
        if (animating) {
            requestRender()
        }
    }

    /**
     * Asks the loader thread to re-read `state.json`.
     *
     * [immediate] skips the crossfade, which is what a home/lock surface switch
     * wants: the screen is already transitioning, and fading between the two
     * effect images would be visible on unlock.
     *
     * The load is a cheap JSON read when neither the artwork nor its effect
     * image changed, so this is also the safety net for a `reload` call that
     * was lost while the engine was being recreated.
     */
    fun requestReload(immediate: Boolean = false) {
        if (immediate) immediateNextLoad = true
        if (destroyed) return
        if (!reloadInFlight.compareAndSet(false, true)) {
            reloadAgain.set(true)
            return
        }
        try {
            loader.execute {
                val immediateNow = immediateNextLoad
                immediateNextLoad = false
                val loaded = loadFrame(immediateNow)
                if (destroyed) {
                    loaded?.recycle()
                    reloadInFlight.set(false)
                    return@execute
                }
                publish(loaded)
                reloadInFlight.set(false)
                if (reloadAgain.compareAndSet(true, false)) {
                    requestReload()
                } else {
                    // Nothing to show yet; keep the surface switch pending so the
                    // next successful load does not fade between home and lock.
                    if (loaded == null) immediateNextLoad = immediateNow
                    drainPendingAdvance()
                }
            }
        } catch (e: RejectedExecutionException) {
            // The engine was destroyed between the check and the submit.
            reloadInFlight.set(false)
            Log.d(TAG, "reload ignored after renderer shutdown")
        }
    }

    /** Hands a decoded frame to the GL thread; the newest one wins. */
    private fun publish(loaded: LoadedFrame?) {
        val previous = pending
        pending = loaded
        previous?.recycle()
        requestRender()
    }

    fun setLockScreenVisible(visible: Boolean) {
        if (lockScreenVisible == visible) return
        lockScreenVisible = visible
        Log.d(TAG, "lockScreen.visible=$visible")
        requestReload(immediate = true)
    }

    /**
     * Promotes the prefetched slot on the wallpaper, like Muzei's `next artwork`
     * tap action.
     *
     * The promotion is persisted in `runtime.json` before the crossfade, so a
     * reload (or a process restart) can never fall back to the old current slot;
     * the Flutter side adopts the runtime the next time it runs and refills the
     * freed slot.
     */
    fun requestAdvance() {
        if (destroyed) return
        if (!advanceInFlight.compareAndSet(false, true)) {
            // A promotion is already decoding; keep this tap for right after it.
            enqueueAdvance(SystemClock.elapsedRealtime())
            return
        }
        val requestedAt = SystemClock.elapsedRealtime()
        try {
            loader.execute {
                val loaded = loadNextFrame()
                if (destroyed) {
                    loaded?.recycle()
                    advanceInFlight.set(false)
                    return@execute
                }
                if (loaded == null) {
                    // Flutter bakes one artwork ahead, so a burst of taps can
                    // outrun the refill; replay this one when the prefetch lands.
                    enqueueAdvance(requestedAt)
                }
                publish(loaded)
                advanceInFlight.set(false)
            }
        } catch (e: RejectedExecutionException) {
            advanceInFlight.set(false)
            Log.d(TAG, "advance ignored after renderer shutdown")
        }
    }

    private fun enqueueAdvance(requestedAt: Long) {
        val pending = synchronized(advanceRequests) {
            advanceRequests.request(requestedAt)
            advanceRequests.size
        }
        Log.d(TAG, "advance queued pending=$pending")
    }

    /**
     * Replays one buffered tap once a reload shows a baked next slot.
     *
     * Flutter bakes the next artwork only after it adopts an advance, so the
     * reload that follows a prefetch commit is the moment a buffered tap can be
     * served. Further buffered taps wait for their own prefetch.
     */
    private fun drainPendingAdvance() {
        if (destroyed) return
        if (synchronized(advanceRequests) { advanceRequests.isEmpty }) return
        if (resolveAdvanceTarget() == null) return
        val fresh = synchronized(advanceRequests) {
            advanceRequests.consume(SystemClock.elapsedRealtime())
        }
        if (!fresh) return
        Log.d(TAG, "advance.drain")
        requestAdvance()
    }

    /** The action bound to a gesture, from the latest `state.json`. */
    fun actionFor(threeFinger: Boolean): String = if (threeFinger) threeFingerBinding else doubleTapBinding

    /** Runs a `WallpaperTapAction` value; unknown values are ignored. */
    fun performTapAction(action: String) {
        when (action) {
            ACTION_TEMPORARY_DISABLE -> toggleTemporaryFocus()
            ACTION_NEXT_ARTWORK -> requestAdvance()
            ACTION_VIEW_ARTWORK -> openArtwork()
            else -> Log.d(TAG, "gesture action ignored action=$action")
        }
    }

    /** Touching the wallpaper postpones the re-blur, like Muzei. */
    fun onWallpaperTouch() {
        if (!focused) return
        handler.removeCallbacks(restoreFocusTask)
        handler.postDelayed(restoreFocusTask, TEMPORARY_FOCUS_MS)
    }

    fun setNormalOffsetX(offset: Float) {
        normalOffsetX = offset.coerceIn(0f, 1f)
        requestRender()
    }

    fun setZoom(value: Float) {
        zoom = value.coerceIn(0f, 1f)
        requestRender()
    }

    private fun setFocused(value: Boolean) {
        if (focused == value) return
        focused = value
        requestRender()
    }

    /** Muzei toggles the effects on a tap, then restores them after a delay. */
    private fun toggleTemporaryFocus() {
        val focus = !focused
        setFocused(focus)
        handler.removeCallbacks(restoreFocusTask)
        if (focus) {
            handler.postDelayed(restoreFocusTask, TEMPORARY_FOCUS_MS)
        }
    }

    private fun openArtwork() {
        try {
            context.startActivity(
                Intent(context, MainActivity::class.java)
                    .setAction(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_LAUNCHER)
                    .putExtra("page", "/muzei_wallpaper")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "failed to open the app from the wallpaper", t)
        }
    }

    fun destroy() {
        Log.d(TAG, "renderer.destroy")
        destroyed = true
        synchronized(advanceRequests) { advanceRequests.clear() }
        WallpaperRenderBus.detach(this)
        handler.removeCallbacks(restoreFocusTask)
        loader.shutdownNow()
        pending?.recycle()
        pending = null
        // Deletes happen in the live context before the engine tears it down.
        incoming?.destroy()
        incoming = null
        queued?.destroy()
        queued = null
        current?.destroy()
        current = null
        if (program != 0) {
            GLES20.glDeleteProgram(program)
            program = 0
        }
    }

    private fun consumePending() {
        val loaded = pending ?: return
        pending = null
        // Compare with the newest accepted frame, not with what is on screen: a
        // duplicate load can arrive while the previous one is still fading in.
        if (loaded.identity == targetIdentity) {
            loaded.recycle()
            return
        }
        val frame = upload(loaded)
        targetIdentity = frame.identity
        if (current == null || loaded.immediate) {
            incoming?.destroy()
            incoming = null
            queued?.destroy()
            queued = null
            crossfadeStartNs = 0L
            val old = current
            current = frame
            old?.destroy()
            writeRuntime(frame)
        } else if (incoming == null) {
            incoming = frame
            crossfadeStartNs = System.nanoTime()
        } else {
            // Keep only the newest frame; it is uploaded as soon as the running
            // crossfade finishes.
            queued?.destroy()
            queued = frame
        }
        requestRender()
    }

    /** Uploads [loaded] to the GL thread and recycles its bitmaps. */
    private fun upload(loaded: LoadedFrame): UploadedFrame {
        val width = loaded.sharp.width
        val height = loaded.sharp.height
        val sharpTexture = createTexture(loaded.sharp)
        val effectTexture = loaded.effect?.let(::createTexture) ?: 0
        val frame = UploadedFrame(
            generation = loaded.generation,
            current = loaded.current,
            next = loaded.next,
            identity = loaded.identity,
            sharpTexture = sharpTexture,
            effectTexture = effectTexture,
            aspect = width.toFloat() / height.toFloat(),
            refillRequested = loaded.refillRequested,
        )
        Log.d(
            TAG,
            "texture.loaded generation=${loaded.generation} slot=${loaded.current} " +
                "w=$width h=$height effect=${effectTexture != 0}",
        )
        loaded.recycle()
        return frame
    }

    /** Advances the temporary-focus fade; returns whether another frame is due. */
    private fun tickEffectsAlpha(): Boolean {
        val target = if (focused) 0f else 1f
        if (effectsAlpha == target) return false
        val now = System.nanoTime()
        val deltaMs = if (lastFrameNs == 0L) 0f else ((now - lastFrameNs) / 1_000_000f).coerceAtMost(64f)
        lastFrameNs = now
        val step = deltaMs / FOCUS_MS
        effectsAlpha = if (target > effectsAlpha) {
            min(target, effectsAlpha + step)
        } else {
            max(target, effectsAlpha - step)
        }
        return true
    }

    /** Finishes a crossfade and starts the queued one, if any. */
    private fun tickCrossfade(): Boolean {
        val frame = incoming ?: return false
        if (crossfadeValue() < 1f) return false
        val old = current
        current = frame
        incoming = null
        old?.destroy()
        writeRuntime(frame)
        val next = queued
        queued = null
        if (next != null) {
            incoming = next
            crossfadeStartNs = System.nanoTime()
        }
        return true
    }

    private fun crossfadeValue(): Float {
        if (crossfadeStartNs == 0L) return 1f
        val elapsedMs = (System.nanoTime() - crossfadeStartNs) / 1_000_000f
        return (elapsedMs / CROSSFADE_MS).coerceIn(0f, 1f)
    }

    private fun drawFrames(): Boolean {
        val currentFrame = current ?: return false
        drawFrame(currentFrame, 1f, incoming = false)

        val incomingFrame = incoming ?: return false
        val value = crossfadeValue()
        if (value >= 1f) return false
        drawFrame(incomingFrame, value, incoming = true)
        return true
    }

    /**
     * Draws one frame as sharp + effect.
     *
     * The stationary frame is composed exactly (opaque sharp, effect on top at
     * `effectsAlpha`). The incoming frame is weighted by the crossfade so the
     * two compositions add up: at full effects it fades effect over effect, at
     * full focus sharp over sharp.
     */
    private fun drawFrame(frame: UploadedFrame, alpha: Float, incoming: Boolean) {
        val effectAlpha = if (frame.effectTexture != 0) effectsAlpha else 0f
        if (incoming) {
            if (effectAlpha < 1f) {
                drawTexture(frame.sharpTexture, frame.aspect, alpha * (1f - effectAlpha))
            }
            if (effectAlpha > 0f) {
                drawTexture(frame.effectTexture, frame.aspect, alpha * effectAlpha)
            }
        } else {
            drawTexture(frame.sharpTexture, frame.aspect, alpha)
            if (effectAlpha > 0f) {
                drawTexture(frame.effectTexture, frame.aspect, alpha * effectAlpha)
            }
        }
    }

    private fun drawTexture(texture: Int, aspect: Float, alpha: Float) {
        if (texture == 0 || alpha <= 0f) {
            return
        }
        updateTexCoords(aspect)

        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glUniform1i(uTexture, 0)
        GLES20.glUniform1f(uAlpha, alpha)

        vertexBuffer.position(0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 0, vertexBuffer)

        texCoordBuffer.position(0)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, texCoordBuffer)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
    }

    /**
     * Cover-fit texture coordinates for [aspect], panned by the launcher offset
     * and narrowed by the launcher zoom (Muzei's `GLPictureSet` matrices).
     */
    private fun updateTexCoords(aspect: Float) {
        WallpaperViewport.texCoords(
            texCoords,
            textureAspect = aspect,
            viewAspect = viewWidth.toFloat() / viewHeight.toFloat(),
            offsetX = normalOffsetX,
            zoom = zoom,
        )
        texCoordBuffer.position(0)
        texCoordBuffer.put(texCoords)
        texCoordBuffer.position(0)
    }

    private fun loadFrame(immediate: Boolean): LoadedFrame? {
        return try {
            val state = store.readState() ?: return null
            // Gesture bindings can change without touching the images, so they
            // are refreshed on every load, before the identity short-circuit.
            doubleTapBinding = state.doubleTapAction
            threeFingerBinding = state.threeFingerAction
            val slot = state.displaySlot(store.readRuntime()) ?: return null
            decodeFrame(state, slot, immediate)
        } catch (t: Throwable) {
            Log.e(TAG, "failed to load wallpaper state", t)
            null
        }
    }

    /**
     * Loads the prefetched slot for a native advance and records the promotion
     * in `runtime.json` before the crossfade starts.
     */
    private fun loadNextFrame(): LoadedFrame? {
        return try {
            val target = resolveAdvanceTarget()
            if (target == null) {
                Log.d(TAG, "advance ignored: no prefetched slot")
                return null
            }
            val state = target.state
            doubleTapBinding = state.doubleTapAction
            threeFingerBinding = state.threeFingerAction
            val frame = decodeFrame(state, target.next, immediate = false, refillRequested = true) ?: return null
            val nextSlot = target.next
            store.writeRuntime(
                WallpaperRuntime(
                    generation = state.generation,
                    current = nextSlot.id,
                    next = -1,
                    refillRequested = true,
                ),
            )
            Log.d(TAG, "advance.promote generation=${state.generation} slot=${nextSlot.id}")
            // Ask the running app to adopt this slot and bake the next one; the
            // wallpaper already shows the artwork, so the refill is invisible.
            WallpaperAppBridge.notifyAdvanced()
            frame
        } catch (t: Throwable) {
            Log.e(TAG, "failed to advance the wallpaper", t)
            null
        }
    }

    /** A tap's promotion target, resolved from the state and the runtime. */
    private class AdvanceTarget(val state: WallpaperFileState, val next: WallpaperSlotFiles)

    /** The slot a tap should promote, or null when nothing is baked ahead. */
    private fun resolveAdvanceTarget(): AdvanceTarget? {
        val state = store.readState() ?: return null
        val runtime = store.readRuntime()
        val currentSlot = state.displaySlot(runtime) ?: return null
        // The runtime is the authority between Dart writes: after an advance its
        // `next` is -1, so no tap can be promoted until Dart refills.
        val nextId = runtime?.takeIf { it.generation == state.generation }?.next ?: state.next
        val nextSlot = if (nextId >= 0) state.slots[nextId] else null
        if (nextSlot == null || nextSlot.id == currentSlot.id) return null
        return AdvanceTarget(state, nextSlot)
    }

    private fun decodeFrame(
        state: WallpaperFileState,
        slot: WallpaperSlotFiles,
        immediate: Boolean,
        refillRequested: Boolean = false,
    ): LoadedFrame? {
        val sharpFile = store.resolve(slot.sharp) ?: return null
        val effectFile = slot.effectFor(lockScreenVisible)?.let(store::resolve)
        val effectAvailable = effectFile?.isFile == true
        val identity = identityOf(slot.entryId, effectFile, effectAvailable)
        // A reload that does not change the artwork or its effects (for example
        // a prefetch commit, or a visibility check) must not decode or fade.
        if (identity == targetIdentity) return null
        val sharp = BitmapFactory.decodeFile(sharpFile.absolutePath) ?: run {
            Log.e(TAG, "failed to decode ${sharpFile.absolutePath}")
            return null
        }
        val effect = effectFile?.let { file ->
            BitmapFactory.decodeFile(file.absolutePath) ?: run {
                Log.w(TAG, "failed to decode ${file.absolutePath}")
                null
            }
        }
        return LoadedFrame(
            generation = state.generation,
            current = slot.id,
            // A slot promoted by the runtime is the current one even though the
            // state still lists the old artwork as current.
            next = if (slot.id == state.current) state.next else -1,
            sharp = sharp,
            effect = effect,
            identity = identity,
            immediate = immediate,
            refillRequested = refillRequested,
        )
    }

    /**
     * Identifies the content of a frame, so a reload that does not change the
     * artwork or its effects (for example a prefetch commit) is not crossfaded.
     */
    private fun identityOf(entryId: Int, effectFile: File?, effectDecoded: Boolean): String {
        val effect = if (effectFile != null && effectDecoded) {
            "${effectFile.path}@${effectFile.lastModified()}:${effectFile.length()}"
        } else {
            ""
        }
        return "$entryId|$effect"
    }

    private fun writeRuntime(frame: UploadedFrame) {
        if (frame.generation < 0) return
        try {
            store.writeRuntime(
                WallpaperRuntime(
                    generation = frame.generation,
                    current = frame.current,
                    next = frame.next,
                    refillRequested = frame.refillRequested,
                ),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "failed to write runtime", t)
        }
    }

    private fun loadSpikeTexture() {
        val bitmap = BitmapFactory.decodeResource(context.resources, R.drawable.live_wallpaper_spike)
        if (bitmap == null) {
            Log.e(TAG, "spike bitmap could not be decoded")
            return
        }
        val texture = createTexture(bitmap)
        val aspect = bitmap.width.toFloat() / bitmap.height.toFloat()
        bitmap.recycle()
        current = UploadedFrame(
            generation = -1,
            current = -1,
            next = -1,
            identity = "spike",
            sharpTexture = texture,
            effectTexture = 0,
            aspect = aspect,
            refillRequested = false,
        )
        Log.d(TAG, "texture.spike w=$viewWidth h=$viewHeight")
    }

    private fun createTexture(bitmap: Bitmap): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        val id = textures[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
        return id
    }

    private fun createProgram(vertexSource: String, fragmentSource: String): Int {
        val vertexShader = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragmentShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val id = GLES20.glCreateProgram()
        GLES20.glAttachShader(id, vertexShader)
        GLES20.glAttachShader(id, fragmentShader)
        GLES20.glLinkProgram(id)

        val status = IntArray(1)
        GLES20.glGetProgramiv(id, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(id)
            GLES20.glDeleteProgram(id)
            throw RuntimeException("program link failed: $log")
        }

        GLES20.glDeleteShader(vertexShader)
        GLES20.glDeleteShader(fragmentShader)
        return id
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)

        val status = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw RuntimeException("shader compile failed: $log")
        }
        return shader
    }

    /** Bitmaps decoded off the GL thread, waiting for an upload. */
    private class LoadedFrame(
        val generation: Int,
        val current: Int,
        val next: Int,
        val sharp: Bitmap,
        val effect: Bitmap?,
        val identity: String,
        val immediate: Boolean,
        val refillRequested: Boolean,
    ) {
        fun recycle() {
            if (!sharp.isRecycled) sharp.recycle()
            effect?.let { if (!it.isRecycled) it.recycle() }
        }
    }

    /** GL textures of one artwork plus the state to report in `runtime.json`. */
    private class UploadedFrame(
        val generation: Int,
        val current: Int,
        val next: Int,
        val identity: String,
        val sharpTexture: Int,
        val effectTexture: Int,
        val aspect: Float,
        val refillRequested: Boolean,
    ) {
        fun destroy() {
            val textures = intArrayOf(sharpTexture, effectTexture).filter { it != 0 }.toIntArray()
            if (textures.isNotEmpty()) {
                GLES20.glDeleteTextures(textures.size, textures, 0)
            }
        }
    }
}
