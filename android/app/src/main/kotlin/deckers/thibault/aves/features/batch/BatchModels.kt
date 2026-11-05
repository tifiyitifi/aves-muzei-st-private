package deckers.thibault.aves.features.batch

/**
 * One image the batch job processes.
 *
 * The job is built by Dart from the current selection, so it carries only the
 * fields the native side needs to resolve and name the source. The MediaStore
 * entry id is kept for progress/result correlation, not for lookups.
 */
data class BatchItem(
    val entryId: Long,
    val uri: String,
    val displayName: String,
    val mimeType: String?,
)

/** One configured tool in the job's ordered chain. */
data class BatchToolSpec(
    val id: String,
    val settings: Map<String, Any?>,
)

/**
 * Where and how the processed image is written.
 *
 * [relativePath] is a MediaStore relative path such as `Pictures/aves_batch`.
 * [namePattern] supports `{name}` (source base name) and `{date}` (run time).
 * [format] is `keep` or an explicit encoder key (`jpeg`, `png`, `webp`, ...).
 */
data class BatchOutputSpec(
    val relativePath: String,
    val namePattern: String,
    val format: String,
    val quality: Int,
)

data class BatchJob(
    val jobId: String,
    val items: List<BatchItem>,
    val tools: List<BatchToolSpec>,
    val output: BatchOutputSpec,
)

object BatchJobParser {
    const val DEFAULT_RELATIVE_PATH = "Pictures/aves_batch"

    fun parse(arguments: Any?): BatchJob? {
        val args = arguments as? Map<*, *> ?: return null
        val jobId = args["jobId"] as? String ?: return null
        val rawItems = args["items"] as? List<*> ?: return null
        val rawTools = args["tools"] as? List<*> ?: return null
        val rawOutput = args["output"] as? Map<*, *> ?: return null

        val items = rawItems.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val uri = map["uri"] as? String ?: return@mapNotNull null
            BatchItem(
                entryId = (map["entryId"] as? Number)?.toLong() ?: 0L,
                uri = uri,
                displayName = map["displayName"] as? String ?: uri.substringAfterLast('/'),
                mimeType = map["mimeType"] as? String,
            )
        }
        if (items.isEmpty()) return null

        val tools = rawTools.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val id = map["id"] as? String ?: return@mapNotNull null
            BatchToolSpec(id = id, settings = stringKeyedMap(map["settings"]))
        }

        return BatchJob(
            jobId = jobId,
            items = items,
            tools = tools,
            output = BatchOutputSpec(
                relativePath = (rawOutput["relativePath"] as? String)?.takeIf { it.isNotBlank() } ?: DEFAULT_RELATIVE_PATH,
                namePattern = (rawOutput["namePattern"] as? String)?.takeIf { it.isNotBlank() } ?: "{name}",
                format = rawOutput["format"] as? String ?: "keep",
                quality = ((rawOutput["quality"] as? Number)?.toInt() ?: 100).coerceIn(1, 100),
            ),
        )
    }

    /** Dart maps arrive with non-`String` keys in some channel versions. */
    fun stringKeyedMap(value: Any?): Map<String, Any?> {
        val map = value as? Map<*, *> ?: return emptyMap()
        return map.entries.associate { (key, value) -> key.toString() to value }
    }
}
