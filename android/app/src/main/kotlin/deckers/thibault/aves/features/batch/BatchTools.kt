package deckers.thibault.aves.features.batch

import android.graphics.Color
import android.graphics.RectF
import com.dot.gallery.feature_node.presentation.edit.adjustments.Crop
import com.dot.gallery.feature_node.presentation.edit.adjustments.Flip
import com.dot.gallery.feature_node.presentation.edit.adjustments.Rotate90CW
import com.dot.gallery.feature_node.presentation.edit.adjustments.filters.ImageFilterTypes
import com.dot.gallery.feature_node.presentation.edit.adjustments.varfilter.VariableFilterTypes

/**
 * One batch tool: a small, pure translation from settings to pipeline work.
 *
 * Tools do not decode, encode or write. They only describe what the runner must
 * do, which is what lets the runner keep one decode/encode per image even when
 * several tools are chained (the Aves equivalent of digiKam's `BatchTool`).
 */
interface BatchTool {
    val id: String
    fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>)
}

object BatchToolRegistry {
    private val tools = listOf(
        RefraRecipeTool,
        RefraFilterTool,
        RefraAdjustTool,
        RefraRotateTool,
        RefraFlipTool,
        RefraCropTool,
        ImageResizeTool,
        ImageConvertTool,
        FooterLabelTool,
        FileTimeTool,
    ).associateBy { it.id }

    fun get(id: String): BatchTool? = tools[id]

    fun ids(): Set<String> = tools.keys
}

private object RefraRecipeTool : BatchTool {
    override val id = "refra.recipe"

    override fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>) {
        val rawOps = settings["ops"] as? List<*> ?: return
        val ops = rawOps.mapNotNull { raw ->
            (raw as? Map<*, *>)?.let(BatchJobParser::stringKeyedMap)
        }
        pipeline.adjustments.addAll(AdjustmentCodec.decode(ops))
    }
}

private object RefraFilterTool : BatchTool {
    override val id = "refra.filter"

    override fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>) {
        val name = settings["name"] as? String ?: return
        val type = ImageFilterTypes.values().firstOrNull { it.name.equals(name, ignoreCase = true) } ?: return
        if (type == ImageFilterTypes.Original) return
        val intensity = (settings["intensity"] as? Number)?.toFloat() ?: 1f
        pipeline.adjustments.add(AdjustmentCodec.filterAdjustment(type.createImageFilter(), intensity))
    }
}

private object RefraAdjustTool : BatchTool {
    override val id = "refra.adjust"

    override fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>) {
        val name = settings["name"] as? String ?: return
        val type = VariableFilterTypes.values().firstOrNull { it.name.equals(name, ignoreCase = true) } ?: return
        val value = (settings["value"] as? Number)?.toFloat() ?: type.createDefaultFilter().value
        pipeline.adjustments.add(type.createFilter(value))
    }
}

private object RefraRotateTool : BatchTool {
    override val id = "refra.rotate"

    override fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>) {
        val angle = (settings["angle"] as? Number)?.toFloat() ?: 90f
        pipeline.adjustments.add(Rotate90CW(angle))
    }
}

private object RefraFlipTool : BatchTool {
    override val id = "refra.flip"

    override fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>) {
        pipeline.adjustments.add(Flip(horizontal = settings["horizontal"] == true))
    }
}

private object RefraCropTool : BatchTool {
    override val id = "refra.crop"

    override fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>) {
        val rect = (settings["rect"] as? List<*>)?.mapNotNull { (it as? Number)?.toFloat() } ?: return
        if (rect.size != 4) return
        pipeline.adjustments.add(Crop(RectF(rect[0], rect[1], rect[2], rect[3])))
    }
}

private object ImageResizeTool : BatchTool {
    override val id = "image.resize"

    override fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>) {
        val maxLongEdge = (settings["maxLongEdge"] as? Number)?.toInt()?.takeIf { it > 0 }
        val percent = (settings["percent"] as? Number)?.toInt()?.takeIf { it in 1..100 }
        if (maxLongEdge == null && percent == null) return
        pipeline.resize = ResizeSpec(maxLongEdge = maxLongEdge, percent = percent)
    }
}

private object ImageConvertTool : BatchTool {
    override val id = "image.convert"

    override fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>) {
        pipeline.format = (settings["format"] as? String)?.takeIf { it.isNotBlank() }
        pipeline.quality = (settings["quality"] as? Number)?.toInt()?.coerceIn(1, 100)
    }
}

private object FooterLabelTool : BatchTool {
    override val id = "decorate.footer"

    override fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>) {
        pipeline.footer = FooterSpec(
            text = (settings["text"] as? String)?.takeIf { it.isNotBlank() },
            bandHeightPercent = ((settings["bandHeightPercent"] as? Number)?.toInt() ?: 8).coerceIn(1, 40),
            textSizePercent = ((settings["textSizePercent"] as? Number)?.toInt() ?: 55).coerceIn(10, 90),
            background = (settings["background"] as? Number)?.toInt() ?: Color.WHITE,
            foreground = (settings["foreground"] as? Number)?.toInt() ?: Color.BLACK,
            atTop = settings["atTop"] == true,
        )
    }
}

private object FileTimeTool : BatchTool {
    override val id = "file.time"

    override fun apply(pipeline: BatchPipeline, settings: Map<String, Any?>) {
        pipeline.refreshTime = settings["enabled"] != false
    }
}
