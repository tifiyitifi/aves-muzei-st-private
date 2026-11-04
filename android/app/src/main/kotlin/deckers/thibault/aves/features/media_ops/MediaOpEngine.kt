package deckers.thibault.aves.features.media_ops

/**
 * Which implementation handles a media file operation.
 *
 * `V1` keeps the legacy pipeline untouched, so switching back is a preference
 * change and never a code change. `V2` is the batched pipeline in this package.
 */
enum class MediaOpEngine {
    V1, V2;

    companion object {
        /** New installs run the fast pipeline. */
        val DEFAULT = V2

        /** Unknown or missing values fall back to the default, never to the legacy path. */
        fun fromName(name: String?): MediaOpEngine = values().firstOrNull { it.name.equals(name, ignoreCase = true) } ?: DEFAULT
    }
}
