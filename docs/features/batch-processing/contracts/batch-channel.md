# Batch channel contract

The Dart ↔ Kotlin seam for batch processing. Two channels, both owned by the
feature and registered in `MainActivity`.

| Channel | Type | Name |
| --- | --- | --- |
| Job stream | `StreamsChannel` | `deckers.thibault/aves/batch_stream` |
| Control | `MethodChannel` | `deckers.thibault/aves/batch` |

## Job stream

Subscribing to the stream starts the job: the stream arguments **are** the job.
There is no separate `start` call. The stream ends with `endOfStream` after
`jobDone`.

### Job map

```text
{
  jobId:        String,             // unique per run
  items: [                          // one per source image
    {
      entryId:     int,             // correlation only, never a lookup
      uri:         String,          // source content URI
      displayName: String,          // source file name
      mimeType:    String?          // source MIME type, may be null
    }
  ],
  tools: [                          // enabled tools, in the sheet's order
    { id: String, settings: Map<String, Object?> }
  ],
  output: {
    relativePath: String,           // MediaStore relative path
    namePattern:  String,           // {name} and {date} placeholders
    format:       String,           // "keep" or an encoder key
    quality:      int               // 1..100
  }
}
```

`tools` is built from the enabled actions only (`BatchJob.toMap`), so the native
side never has to ask whether a tool is enabled.

### Tool ids

The id is the contract with `BatchToolRegistry`. A tool is added in three
places: the Dart enum, the native registry, and the view catalog.

| Id | Settings |
| --- | --- |
| `refra.recipe` | `ops`: list of editor adjustment maps |
| `refra.filter` | `name`, `intensity` (0..1) |
| `refra.adjust` | `name`, `value` |
| `refra.rotate` | `angle` (degrees) |
| `refra.flip` | `horizontal` (bool) |
| `refra.crop` | `rect`: `[left, top, right, bottom]`, normalised 0..1 |
| `image.resize` | `maxLongEdge` (px) or `percent` (1..100) |
| `image.convert` | `format`, `quality` |
| `decorate.footer` | `text`, `bandHeightPercent`, `textSizePercent`, `atTop`; native also reads `background`, `foreground` |
| `file.time` | `enabled` |

Unknown settings keys are ignored. Unknown tool ids are skipped (`RUN-6`).

### Name pattern

- `{name}` — the source base name.
- `{date}` — the run time.

The pattern is chosen by the Dart side: `{name}` for replace previous,
`{name}_{date}` for keep versions and for copy & share. The native side applies
the pattern and reports the name the MediaStore actually assigned, which can
include a ` (1)` suffix.

Copy & share has no supersede pass, so it always dates its copies; a plain name
would collide between two runs on the same source.

### Job kinds

Batch processing and copy & share send the same job map. Only
`output.relativePath` differs: `Pictures/aves_batch_results` for batch results,
`Pictures/aves_share` for share copies. The native side has no notion of a run
kind, and needs none: the relative path is the whole difference.

The Dart reader still gates recording on the batch root, so a share job's
`itemDone` events are dropped (`SHR-6`).

### Events

| `type` | Keys | Meaning |
| --- | --- | --- |
| `jobStarted` | `jobId`, `itemCount` | the job accepted its arguments |
| `itemStarted` | `index`, `entryId` | an item is about to be processed |
| `itemProgress` | — | reserved; the executor does not emit it |
| `itemDone` | `index`, `entryId`, `uri`, `path`, `name`, `size`, `mimeType` | the result was written |
| `itemFailed` | `index`, `entryId`, `message` | the item did not produce a file |
| `jobDone` | `jobId`, `done`, `failed`, `cancelled` | terminal event |

`itemDone` carries the facts read back from the MediaStore row the job just
wrote, not the requested name. The recorder stores them as-is (`REC-3`).

Rules for the Dart reader:

- an unknown `type` is dropped, not an error;
- a missing numeric field falls back to the current value;
- `jobDone` is always the last event;
- recording happens on `itemDone` only (`REC-1`, `REC-2`).

## Control channel

| Method | Arguments | Returns | Notes |
| --- | --- | --- | --- |
| `cancel` | `jobId` | `null` | adds the id to the cancelled set; the executor skips the remaining items |
| `replaceWithResult` | `sourceUri`, `resultUri` | `bool` | overwrites the source in place, consumes the result |
| `requestWriteAccess` | `uris`, `mimeTypes` | `bool` | one system request for the batch; a denial is not an error |
| `deleteResult` | `resultUri` | `bool` | permanent delete, bypasses the recycle-bin setting; used for a consumed result, a superseded result and an expired share copy |

### `replaceWithResult`

1. Query the result file's display name and MIME type from the MediaStore.
2. Write the result bytes into the source through `overrideImageStreaming`, which
   keeps the source's date columns and restores the original on failure.
3. If the display name differs, update the source row's name and MIME type.
4. Delete the result file.
5. Return `true` only if the write succeeded.

A `false` return leaves the result row pending (`APP-2`).

### `requestWriteAccess`

- Content URIs only; anything else is filtered out.
- Chunked by the caller at 2000 URIs, the `MediaStore.createWriteRequest` limit.
- Returns whether the request was granted. The caller proceeds either way: files
  the app owns can still be written.

### `deleteResult`

Permanent. Used for a consumed result, a superseded result parked as
`<name>-to-remove`, and an expired share copy. It intentionally does not consult
the app's delete setting: a consumed or expired copy in the recycle bin is noise,
not a safety net.

## Compatibility

- Adding a tool: new id in both registries, new catalog entry. A profile saved
  before the tool existed still loads (`PRF-7`).
- Adding an event field: optional on the Dart side; the reader defaults it.
- Adding a method: `notImplemented` is answered for anything the handler does not
  know, so an older app ignores a newer call.
- Removing a tool: keep the id in the Dart enum long enough to decode old
  profiles, or let `tryFromJson` drop the action.
- Copy & share needs no native change: it is the same job map with another
  `output.relativePath`. `deleteResult` gained a third caller (retention), not a
  new behaviour.
