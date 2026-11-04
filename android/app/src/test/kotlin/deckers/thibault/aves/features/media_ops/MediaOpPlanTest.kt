package deckers.thibault.aves.features.media_ops

import deckers.thibault.aves.storage.apis.StorageApi
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class MediaOpPlanTest {
    private val api29 = 29 // MediaStorePermissions cannot request bulk access
    private val api30 = 30

    @Test
    fun mediaStoreMoveNeedsSameVolumeAndAllowedDirectory() {
        assertEquals(StorageApi.MEDIA_STORE, MediaOpPlan.selectMoveApi(StorageApi.MEDIA_STORE, StorageApi.MEDIA_STORE, sourceInMediaStore = true, sameVolume = true, canMoveToPath = true, copy = false, sdkInt = api29))
        // cross-volume moves cannot go through the Media Store
        assertNull(MediaOpPlan.selectMoveApi(StorageApi.MEDIA_STORE, StorageApi.MEDIA_STORE, sourceInMediaStore = true, sameVolume = false, canMoveToPath = true, copy = false, sdkInt = api29))
        // the target primary directory must be allowed for the MIME type
        assertNull(MediaOpPlan.selectMoveApi(StorageApi.MEDIA_STORE, StorageApi.MEDIA_STORE, sourceInMediaStore = true, sameVolume = true, canMoveToPath = false, copy = false, sdkInt = api29))
        // copies keep the legacy SAF path rather than re-inserting a row
        assertNull(MediaOpPlan.selectMoveApi(StorageApi.MEDIA_STORE, StorageApi.MEDIA_STORE, sourceInMediaStore = true, sameVolume = true, canMoveToPath = true, copy = true, sdkInt = api29))
        // `RELATIVE_PATH` moves need Android 10
        assertNull(MediaOpPlan.selectMoveApi(StorageApi.MEDIA_STORE, StorageApi.MEDIA_STORE, sourceInMediaStore = true, sameVolume = true, canMoveToPath = true, copy = false, sdkInt = 28))
    }

    @Test
    fun sameVolumeRowMoveBeatsDirectFileAccess() {
        // an entry indexed by the Media Store keeps using its row even when both
        // directories grant file access, as renaming the file would need a scan
        assertEquals(StorageApi.MEDIA_STORE, MediaOpPlan.selectMoveApi(StorageApi.FILE, StorageApi.FILE, sourceInMediaStore = true, sameVolume = true, canMoveToPath = true, copy = false, sdkInt = api29))
        assertEquals(StorageApi.MEDIA_STORE, MediaOpPlan.selectMoveApi(StorageApi.FILE, StorageApi.MEDIA_STORE, sourceInMediaStore = true, sameVolume = true, canMoveToPath = true, copy = false, sdkInt = api30))
        // without a Media Store row there is nothing to update
        assertEquals(StorageApi.FILE, MediaOpPlan.selectMoveApi(StorageApi.FILE, StorageApi.FILE, sourceInMediaStore = false, sameVolume = true, canMoveToPath = true, copy = false, sdkInt = api29))
    }

    @Test
    fun fileMoveWhenBothSidesAllowFileAccess() {
        assertEquals(StorageApi.FILE, MediaOpPlan.selectMoveApi(StorageApi.FILE, StorageApi.FILE, sourceInMediaStore = false, sameVolume = true, canMoveToPath = false, copy = false, sdkInt = api29))
        assertEquals(StorageApi.FILE, MediaOpPlan.selectMoveApi(StorageApi.FILE, StorageApi.FILE, sourceInMediaStore = false, sameVolume = true, canMoveToPath = false, copy = true, sdkInt = api29))
    }

    @Test
    fun directFileCopyIsAllowedOnApi30WithMixedAccess() {
        assertEquals(StorageApi.FILE, MediaOpPlan.selectMoveApi(StorageApi.MEDIA_STORE, StorageApi.FILE, sourceInMediaStore = true, sameVolume = true, canMoveToPath = false, copy = true, sdkInt = api30))
        // moving a row that cannot be updated still relies on the SAF copy-then-delete fallback
        assertNull(MediaOpPlan.selectMoveApi(StorageApi.MEDIA_STORE, StorageApi.FILE, sourceInMediaStore = true, sameVolume = true, canMoveToPath = false, copy = false, sdkInt = api30))
        // direct file copy is only trusted from Android 11
        assertNull(MediaOpPlan.selectMoveApi(StorageApi.MEDIA_STORE, StorageApi.FILE, sourceInMediaStore = true, sameVolume = true, canMoveToPath = false, copy = true, sdkInt = api29))
    }

    @Test
    fun missingOrSafAccessFallsBackToSaf() {
        assertNull(MediaOpPlan.selectMoveApi(null, null, sourceInMediaStore = false, sameVolume = true, canMoveToPath = false, copy = false, sdkInt = api30))
        assertNull(MediaOpPlan.selectMoveApi(StorageApi.SAF, StorageApi.SAF, sourceInMediaStore = false, sameVolume = true, canMoveToPath = false, copy = false, sdkInt = api30))
        assertNull(MediaOpPlan.selectMoveApi(StorageApi.FILE, null, sourceInMediaStore = false, sameVolume = true, canMoveToPath = false, copy = false, sdkInt = api30))
        assertNull(MediaOpPlan.selectMoveApi(StorageApi.SAF, StorageApi.SAF, sourceInMediaStore = true, sameVolume = true, canMoveToPath = false, copy = false, sdkInt = api30))
    }

    @Test
    fun promptNeedsConsentForegroundActivityAndBulkApi() {
        assertTrue(MediaOpPlan.canRequestPrompt(allowPrompt = true, sdkInt = api30, uriCount = 10, activityReady = true))
        assertFalse(MediaOpPlan.canRequestPrompt(allowPrompt = false, sdkInt = api30, uriCount = 10, activityReady = true))
        assertFalse(MediaOpPlan.canRequestPrompt(allowPrompt = true, sdkInt = api29, uriCount = 10, activityReady = true))
        assertFalse(MediaOpPlan.canRequestPrompt(allowPrompt = true, sdkInt = api30, uriCount = 10, activityReady = false))
        assertFalse(MediaOpPlan.canRequestPrompt(allowPrompt = true, sdkInt = api30, uriCount = 0, activityReady = true))
        assertTrue(MediaOpPlan.canRequestPrompt(allowPrompt = true, sdkInt = api30, uriCount = MediaOpPlan.MAX_BULK_URIS, activityReady = true))
        assertFalse(MediaOpPlan.canRequestPrompt(allowPrompt = true, sdkInt = api30, uriCount = MediaOpPlan.MAX_BULK_URIS + 1, activityReady = true))
    }

    @Test
    fun engineParsingFallsBackToTheFastPipeline() {
        assertEquals(MediaOpEngine.V1, MediaOpEngine.fromName("v1"))
        assertEquals(MediaOpEngine.V2, MediaOpEngine.fromName("v2"))
        assertEquals(MediaOpEngine.V2, MediaOpEngine.fromName("nope"))
        assertEquals(MediaOpEngine.V2, MediaOpEngine.fromName(null))
    }
}
