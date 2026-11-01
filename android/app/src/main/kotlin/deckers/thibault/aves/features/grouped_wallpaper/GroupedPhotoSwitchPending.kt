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

/**
 * Decides when the bar may stop saying "switching to the next photo".
 *
 * A slot id alone is not enough: a re-bake can keep the id and change the photo
 * it draws, so the pair identifies the frame on screen. Arrival is "the bar is
 * no longer describing the photo the tap left".
 */
object GroupedPhotoSwitchPending {
    fun isSamePhoto(fromSlotId: Int, fromEntryId: Int, slotId: Int?, slotEntryId: Int?): Boolean =
        slotId != null && slotEntryId != null && slotId == fromSlotId && slotEntryId == fromEntryId

    /**
     * Whether a switch that started [elapsedMs] ago should still be shown.
     *
     * The timeout matters because a bake can fail: the bar must return to the
     * photo that is really on screen instead of staying in the switching state.
     */
    fun stillWaiting(samePhoto: Boolean, elapsedMs: Long, timeoutMs: Long): Boolean = samePhoto && elapsedMs <= timeoutMs
}
