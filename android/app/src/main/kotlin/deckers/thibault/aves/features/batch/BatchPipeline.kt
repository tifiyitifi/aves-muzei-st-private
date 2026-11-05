package deckers.thibault.aves.features.batch

import com.dot.gallery.feature_node.domain.model.editor.Adjustment

/**
 * The footer band drawn below (or above) the processed image.
 *
 * [text] is null for the automatic mode, where the final file name is used. All
 * sizes are percentages so the band scales with the image instead of looking
 * different on every resolution.
 */
data class FooterSpec(
    val text: String?,
    val bandHeightPercent: Int,
    val textSizePercent: Int,
    val background: Int,
    val foreground: Int,
    val atTop: Boolean,
)

/** Output resizing, applied after the geometry adjustments and before the footer. */
data class ResizeSpec(
    val maxLongEdge: Int?,
    val percent: Int?,
)

/**
 * What a chain of tools accumulates for one image.
 *
 * Tools never touch pixels themselves. They describe the work here, and
 * [RefraBakeRunner] performs a single decode, the whole adjustment replay, the
 * optional resize/footer composite, and a single encode. This is the Aves
 * equivalent of digiKam's in-memory `DImg` chain: encoding once per item keeps
 * both quality and time predictable.
 */
class BatchPipeline {
    val adjustments = mutableListOf<Adjustment>()
    var resize: ResizeSpec? = null
    var footer: FooterSpec? = null
    var format: String? = null
    var quality: Int? = null
    var refreshTime: Boolean = false
}
