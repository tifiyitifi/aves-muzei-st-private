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
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.GLUtils
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.min

/**
 * Draws the baked queue and promotes slots on a wallpaper tap.
 *
 * The engine bakes a small queue (`current → next → next2`), so a tap can move
 * to the next photo without waiting for Flutter: the renderer switches to the
 * texture it already uploaded, records what it did in `runtime.json`, and asks
 * the app (or the background worker) to bake the slot it left behind.
 *
 * File reads and PNG decodes happen on a loader thread; the GL thread only
 * uploads the decoded bitmaps, so a slow disk never stalls a frame.
 */
class GroupedWallpaperRenderer(
    private val context: Context,
    private val requestRender: () -> Unit,
    private val onAdvanced: () -> Unit,
) : GLSurfaceView.Renderer {
    private companion object {
        const val TAG = "AvesGroupedWallpaper"

        /** Conservative `GL_MAX_TEXTURE_SIZE` floor, matching the Dart baker. */
        const val MAX_TEXTURE_SIZE = 4096

        const val PLACEHOLDER_SIZE = 256

        /** Neutral grey behind the placeholder glyph. */
        const val PLACEHOLDER_BACKGROUND = 0xFF303338.toInt()

        const val PLACEHOLDER_FOREGROUND = 0xFF8A8F98.toInt()

        const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = aTexCoord;
            }
        """

        const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform sampler2D uTexture;
            varying vec2 vTexCoord;
            void main() {
                gl_FragColor = texture2D(uTexture, vTexCoord);
            }
        """
    }

    /** What the loader thread decoded for one reload. */
    private class LoadedFrame(
        val state: GroupedWallpaperFileState,
        val bitmaps: Map<Int, Bitmap>,
    )

    private class UploadedSlot(val entryId: Int, val photo: String, val texture: Int, val aspect: Float)

    /** Disk reads and PNG decodes never run on the GL thread. */
    private val loader = Executors.newSingleThreadExecutor()

    private val reloadInFlight = AtomicBoolean(false)
    private val reloadAgain = AtomicBoolean(false)

    @Volatile
    private var destroyed = false

    /** Decoded by [loader], uploaded by the GL thread. */
    @Volatile
    private var pending: LoadedFrame? = null

    /** The last state read from disk, used for gestures and the runtime. */
    @Volatile
    private var state: GroupedWallpaperFileState? = null

    /** The slot on screen; a local promotion moves it before Dart writes. */
    @Volatile
    private var displayed: Int = -1

    /** Slot ids whose texture is uploaded, so a promotion never targets a hole. */
    @Volatile
    private var readySlots: Set<Int> = emptySet()

    /**
     * Guards a promotion: a tap arrives on the main thread while a reload is
     * consumed on the GL thread, and both may promote.
     */
    private val advanceLock = Any()

    /** Taps that arrived before a slot was uploaded; replayed as slots land. */
    private val advanceRequests = GroupedAdvanceRequestQueue()

    @Volatile
    private var offsetX = 0.5f

    /** The lock screen is drawn; the lock effect image applies. */
    @Volatile
    private var lockScreenVisible = false

    private var program = 0
    private var aPosition = -1
    private var aTexCoord = -1
    private var uTexture = -1

    private var viewWidth = 1
    private var viewHeight = 1

    private val textures = mutableMapOf<Int, UploadedSlot>()

    private var placeholderTexture = 0

    private val texCoords = FloatArray(8)

    private val fullVertexBuffer: FloatBuffer = ByteBuffer
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

    private val placeholderVertexBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(4 * 2 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()

    private val placeholderTexCoords: FloatBuffer = ByteBuffer
        .allocateDirect(4 * 2 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            // Bitmap row 0 is the top row, so the top of the quad samples v=1.
            put(floatArrayOf(0f, 1f, 1f, 1f, 0f, 0f, 1f, 0f))
            position(0)
        }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        Log.d(TAG, "surface.created")
        destroyed = false
        // A new EGL context invalidates every texture id from the previous one.
        textures.clear()
        readySlots = emptySet()
        placeholderTexture = 0
        try {
            program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            aPosition = GLES20.glGetAttribLocation(program, "aPosition")
            aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
            uTexture = GLES20.glGetUniformLocation(program, "uTexture")
            GLES20.glDisable(GLES20.GL_DEPTH_TEST)
            GLES20.glClearColor(
                ((PLACEHOLDER_BACKGROUND shr 16) and 0xFF) / 255f,
                ((PLACEHOLDER_BACKGROUND shr 8) and 0xFF) / 255f,
                (PLACEHOLDER_BACKGROUND and 0xFF) / 255f,
                1f,
            )
            placeholderTexture = createTexture(createPlaceholderBitmap())
            GroupedWallpaperRenderBus.attach(this)
            requestReload()
        } catch (t: Throwable) {
            // A driver that refuses the program still gets the grey background
            // instead of a black or frozen surface.
            Log.e(TAG, "renderer init failed, falling back to the background color", t)
            program = 0
            placeholderTexture = 0
        }
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        Log.d(TAG, "surface.changed w=$width h=$height")
        viewWidth = width.coerceAtLeast(1)
        viewHeight = height.coerceAtLeast(1)
        GLES20.glViewport(0, 0, viewWidth, viewHeight)
        updatePlaceholderQuad()
        requestRender()
    }

    override fun onDrawFrame(gl: GL10?) {
        consumePending()

        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        if (program == 0) return

        val slot = textures[displayed]
        if (slot != null) {
            GroupedWallpaperViewport.texCoords(texCoords, slot.aspect, viewWidth.toFloat() / viewHeight.toFloat(), offsetX)
            texCoordBuffer.put(texCoords).position(0)
            drawQuad(fullVertexBuffer, texCoordBuffer, slot.texture)
        } else if (placeholderTexture != 0) {
            drawQuad(placeholderVertexBuffer, placeholderTexCoords, placeholderTexture)
        }
    }

    /** Re-reads `state.json` on the loader thread. */
    fun requestReload() {
        if (destroyed) return
        if (!reloadInFlight.compareAndSet(false, true)) {
            reloadAgain.set(true)
            return
        }
        try {
            loader.execute {
                val loaded = loadFrame()
                if (destroyed) {
                    loaded?.bitmaps?.values?.forEach { it.recycle() }
                    reloadInFlight.set(false)
                    return@execute
                }
                pending = loaded
                requestRender()
                reloadInFlight.set(false)
                if (reloadAgain.compareAndSet(true, false)) requestReload()
            }
        } catch (e: RejectedExecutionException) {
            // The engine was destroyed between the check and the submit.
            reloadInFlight.set(false)
            Log.d(TAG, "reload ignored after renderer shutdown")
        }
    }

    /** Launcher offset in `0..1`; single-page launchers report `0.5`. */
    fun setOffsetX(value: Float) {
        val next = value.coerceIn(0f, 1f)
        if (offsetX == next) return
        offsetX = next
        requestRender()
    }

    /**
     * Switches to the home or lock effect image.
     *
     * A reload picks the new file, so the effect never needs a second texture per
     * slot: only the surface being drawn is uploaded.
     */
    fun setLockScreenVisible(visible: Boolean) {
        if (lockScreenVisible == visible) return
        lockScreenVisible = visible
        Log.d(TAG, "lockScreen.visible=$visible")
        requestReload()
    }

    /** The action bound to a gesture, from the latest `state.json`. */
    fun actionFor(threeFinger: Boolean): String {
        val current = state ?: return if (threeFinger) GroupedWallpaperFileState.ACTION_VIEW_ARTWORK else GroupedWallpaperFileState.ACTION_NEXT_ARTWORK
        return if (threeFinger) current.threeFinger else current.doubleTap
    }

    /**
     * Moves to the prefetched slot, as a wallpaper tap does.
     *
     * Returns false when there is nothing to promote: the group is locked or
     * turned off, the queue is exhausted, or the texture of the next slot has
     * not been uploaded yet. The caller then buffers the tap instead of losing
     * it.
     */
    fun promote(): Boolean = synchronized(advanceLock) { promoteLocked() }

    private fun promoteLocked(): Boolean {
        val current = state ?: return false
        if (!current.canPromote) return false
        val nextId = current.next
        if (!readySlots.contains(nextId)) {
            Log.d(TAG, "promote skipped: slot $nextId is not uploaded yet")
            return false
        }
        val nextNext = current.next2
        displayed = nextId
        state = current.copy(current = nextId, next = nextNext, next2 = -1)
        requestRender()
        // Written synchronously: the app reads the runtime as soon as it hears
        // about the tap, and an asynchronous write would let it bake from the
        // slot the tap already left.
        GroupedWallpaperStateFile.writeRuntime(context, current.generation, nextId, nextNext, refillRequested = true)
        Log.d(TAG, "promote generation=${current.generation} current=$nextId next=$nextNext")
        return true
    }

    /** Buffers a tap whose slot is not uploaded yet, so it is not lost. */
    fun enqueueAdvance() {
        val pending = synchronized(advanceLock) {
            advanceRequests.request(SystemClock.elapsedRealtime())
            advanceRequests.size
        }
        Log.d(TAG, "advance queued pending=$pending")
    }

    /**
     * Replays one buffered tap once a reload has uploaded a promotable slot.
     *
     * A tap can outrun the bake; the reload that follows a refill is the moment
     * it can be served. Further buffered taps wait for their own refill.
     */
    private fun drainPendingAdvance() {
        if (destroyed) return
        val promoted = synchronized(advanceLock) {
            val current = state
            if (advanceRequests.isEmpty || current == null) return@synchronized false
            if (!current.canPromote || !readySlots.contains(current.next)) return@synchronized false
            if (!advanceRequests.consume(SystemClock.elapsedRealtime())) return@synchronized false
            promoteLocked()
        }
        if (!promoted) return
        Log.d(TAG, "advance.drain")
        onAdvanced()
    }

    fun destroy() {
        destroyed = true
        GroupedWallpaperRenderBus.detach(this)
        synchronized(advanceLock) { advanceRequests.clear() }
        loader.shutdownNow()
    }

    private fun loadFrame(): LoadedFrame? {
        val state = GroupedWallpaperStateFile.read(context) ?: return null
        val bitmaps = mutableMapOf<Int, Bitmap>()
        for (slot in state.slots) {
            val file = GroupedWallpaperStateFile.photoFile(context, slot.photoFor(lockScreenVisible)) ?: continue
            decode(file)?.let { bitmaps[slot.id] = it }
        }
        return LoadedFrame(state, bitmaps)
    }

    private fun decode(file: File): Bitmap? = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        var sample = 1
        while (bounds.outWidth / sample > MAX_TEXTURE_SIZE || bounds.outHeight / sample > MAX_TEXTURE_SIZE) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        BitmapFactory.decodeFile(file.absolutePath, options)
    } catch (t: Throwable) {
        // A corrupt bake shows the placeholder instead of crashing the service.
        Log.w(TAG, "failed to decode ${file.name}", t)
        null
    }

    private fun consumePending() {
        val loaded = pending ?: return
        pending = null
        val previousGeneration: Int
        val next: GroupedWallpaperFileState
        // Serialized with a promotion: the two threads must not swap the state
        // and the displayed slot under each other.
        synchronized(advanceLock) {
            previousGeneration = state?.generation ?: Int.MIN_VALUE
            // A newer state can still point at the slot a local promotion just
            // left; keep what is on screen instead of rewinding to it.
            next = keepDisplayedSlot(loaded.state, previousGeneration)
            state = next
        }

        val seen = mutableSetOf<Int>()
        for ((id, bitmap) in loaded.bitmaps) {
            seen.add(id)
            val slot = next.slot(id)
            val photo = slot?.photoFor(lockScreenVisible) ?: ""
            val existing = textures[id]
            // A slot keeps its id while it stays in the queue, so an unchanged
            // file must not be uploaded again.
            if (existing != null && slot != null && existing.entryId == slot.entryId && existing.photo == photo) {
                bitmap.recycle()
                continue
            }
            try {
                val aspect = bitmap.width.toFloat() / bitmap.height.toFloat().coerceAtLeast(1f)
                if (existing == null) {
                    textures[id] = UploadedSlot(slot?.entryId ?: -1, photo, createTexture(bitmap), aspect)
                } else {
                    upload(existing.texture, bitmap)
                    textures[id] = UploadedSlot(slot?.entryId ?: -1, photo, existing.texture, aspect)
                }
            } finally {
                bitmap.recycle()
            }
        }

        // Drop the textures of slots that left the queue.
        val stale = textures.keys.filter { !seen.contains(it) }
        for (id in stale) {
            textures.remove(id)?.let { deleteTexture(it.texture) }
        }
        readySlots = textures.keys.toSet()

        synchronized(advanceLock) {
            // A newer state wins; an unchanged one must not undo a local
            // promotion. A tap during the uploads already moved `state` on, and
            // its displayed slot must survive.
            if (state === next) {
                if (next.generation > previousGeneration || !textures.containsKey(displayed)) {
                    displayed = next.current
                }
            }
            if (!textures.containsKey(displayed)) displayed = -1
        }
        // A buffered tap may be servable now that the new slots are uploaded.
        drainPendingAdvance()
    }

    /**
     * Keeps the slot on screen when a newer state is behind it.
     *
     * The app can bake from a runtime it read before a promotion landed, so a
     * new state sometimes still points at the slot the tap already left. Keeping
     * the displayed slot and shifting the queue forward avoids the visible
     * rewind, and the runtime is rewritten with the new generation so Dart adopts
     * the move instead of baking from the stale queue again.
     */
    private fun keepDisplayedSlot(newState: GroupedWallpaperFileState, previousGeneration: Int): GroupedWallpaperFileState {
        if (newState.generation <= previousGeneration) return newState
        val onScreen = displayed
        if (onScreen < 0) return newState
        val queue = listOf(newState.current, newState.next, newState.next2)
        val index = queue.indexOf(onScreen)
        // Only a queued slot ahead of the new current is a promotion to keep.
        if (index <= 0) return newState
        val current = queue[index]
        val next = if (index + 1 < queue.size) queue[index + 1] else -1
        GroupedWallpaperStateFile.writeRuntime(context, newState.generation, current, next, refillRequested = true)
        Log.d(TAG, "reload kept displayed=$onScreen over current=${newState.current}")
        return newState.copy(current = current, next = next, next2 = -1)
    }

    private fun drawQuad(vertices: FloatBuffer, coords: FloatBuffer, texture: Int) {
        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glUniform1i(uTexture, 0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 0, vertices)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, coords)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
    }

    /** Keeps the placeholder glyph square, centered and independent of the aspect. */
    private fun updatePlaceholderQuad() {
        val side = min(viewWidth, viewHeight) * 0.26f
        val halfWidth = side / viewWidth
        val halfHeight = side / viewHeight
        placeholderVertexBuffer
            .put(floatArrayOf(-halfWidth, -halfHeight, halfWidth, -halfHeight, -halfWidth, halfHeight, halfWidth, halfHeight))
            .position(0)
    }

    /**
     * A grey rounded frame with a slash: the "no wallpaper" state, drawn at
     * runtime so the service needs no drawable and cannot fail on a missing one.
     */
    private fun createPlaceholderBitmap(): Bitmap {
        val size = PLACEHOLDER_SIZE
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = PLACEHOLDER_FOREGROUND
            style = Paint.Style.STROKE
            strokeWidth = size * 0.045f
            strokeCap = Paint.Cap.ROUND
        }
        val inset = size * 0.18f
        val rect = RectF(inset, inset, size - inset, size - inset)
        val radius = size * 0.12f
        canvas.drawRoundRect(rect, radius, radius, paint)
        canvas.drawLine(rect.left + size * 0.06f, rect.bottom - size * 0.06f, rect.right - size * 0.06f, rect.top + size * 0.06f, paint)
        return bitmap
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

    private fun upload(texture: Int, bitmap: Bitmap) {
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
    }

    private fun deleteTexture(texture: Int) {
        GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
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
}
