package deckers.thibault.aves.features.batch

import android.graphics.RectF
import androidx.compose.ui.graphics.ColorMatrix
import com.dot.gallery.feature_node.domain.model.editor.Adjustment
import com.dot.gallery.feature_node.domain.model.editor.ImageFilter
import com.dot.gallery.feature_node.presentation.edit.adjustments.Crop
import com.dot.gallery.feature_node.presentation.edit.adjustments.Flip
import com.dot.gallery.feature_node.presentation.edit.adjustments.MatrixAdjustment
import com.dot.gallery.feature_node.presentation.edit.adjustments.Rotate90CW
import com.dot.gallery.feature_node.presentation.edit.adjustments.filters.ImageFilterTypes
import com.dot.gallery.feature_node.presentation.edit.adjustments.varfilter.VariableFilterTypes

/**
 * Turns the batch recipe (plain maps shared with Dart) into the editor's
 * resolution-independent [Adjustment] list.
 *
 * v1 deliberately covers only the deterministic editor operations: colour
 * filters, variable adjustments and geometry. Markup and cut-out are bitmap or
 * mask based, so they are rejected here instead of being silently dropped: a
 * recipe that cannot be reproduced must fail rather than produce a different
 * image.
 */
object AdjustmentCodec {
    fun decode(ops: List<Map<String, Any?>>): List<Adjustment> = ops.map { op ->
        decodeOne(op) ?: throw IllegalArgumentException("unsupported recipe op: ${op["type"]}")
    }

    fun decodeOne(op: Map<String, Any?>): Adjustment? = when (op["type"]) {
        "filter" -> decodeFilter(op)
        "adjust" -> decodeAdjust(op)
        "matrix" -> decodeMatrix(op)
        "rotate" -> Rotate90CW((op["angle"] as? Number)?.toFloat() ?: 90f)
        "flip" -> Flip(op["horizontal"] == true)
        "crop" -> decodeCrop(op)
        else -> null
    }

    /**
     * The effective adjustment for [filter] at [intensity], matching what the
     * editor commits: a partial intensity is baked into a precise colour matrix
     * so the full-resolution replay reproduces the proxy instead of applying the
     * filter at full strength.
     */
    fun filterAdjustment(filter: ImageFilter, intensity: Float): Adjustment {
        val clamped = intensity.coerceIn(0f, 1f)
        val matrix = filter.colorMatrix()
        if (matrix == null || clamped >= 1f) {
            return if (matrix != null) MatrixAdjustment(matrix.values.copyOf(), filter.name) else filter
        }
        return MatrixAdjustment(lerpColorMatrix(identityColorMatrix(), matrix, clamped).values.copyOf(), filter.name)
    }

    private fun decodeFilter(op: Map<String, Any?>): Adjustment? {
        val name = op["name"] as? String ?: return null
        val type = ImageFilterTypes.values().firstOrNull { it.name.equals(name, ignoreCase = true) } ?: return null
        if (type == ImageFilterTypes.Original) return null
        return filterAdjustment(type.createImageFilter(), (op["intensity"] as? Number)?.toFloat() ?: 1f)
    }

    private fun decodeAdjust(op: Map<String, Any?>): Adjustment? {
        val name = op["name"] as? String ?: return null
        val type = VariableFilterTypes.values().firstOrNull { it.name.equals(name, ignoreCase = true) } ?: return null
        val value = (op["value"] as? Number)?.toFloat() ?: type.createDefaultFilter().value
        return type.createFilter(value)
    }

    private fun decodeMatrix(op: Map<String, Any?>): Adjustment? {
        val name = op["name"] as? String ?: return null
        val values = (op["values"] as? List<*>)?.mapNotNull { (it as? Number)?.toFloat() }?.toFloatArray() ?: return null
        if (values.size != 20) return null
        return MatrixAdjustment(values, name)
    }

    private fun decodeCrop(op: Map<String, Any?>): Adjustment? {
        val rect = (op["rect"] as? List<*>)?.mapNotNull { (it as? Number)?.toFloat() } ?: return null
        if (rect.size != 4) return null
        return Crop(RectF(rect[0], rect[1], rect[2], rect[3]))
    }

    private fun identityColorMatrix() = ColorMatrix(
        floatArrayOf(
            1f, 0f, 0f, 0f, 0f,
            0f, 1f, 0f, 0f, 0f,
            0f, 0f, 1f, 0f, 0f,
            0f, 0f, 0f, 1f, 0f,
        ),
    )

    private fun lerpColorMatrix(from: ColorMatrix, to: ColorMatrix, t: Float): ColorMatrix {
        val result = FloatArray(20)
        for (i in 0 until 20) {
            result[i] = from.values[i] + t * (to.values[i] - from.values[i])
        }
        return ColorMatrix(result)
    }
}
