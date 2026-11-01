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

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * A request may only be sent when a channel exists and a handler listens on it.
 *
 * The flag on its own is what made the service and the worker disagree: the
 * background engine set it while no messenger could reach it.
 */
class GroupedRequestListenerTest {
    @Test
    fun `a channel with a handler can serve`() {
        assertTrue(GroupedRequestListener.canServe(messengerAttached = true, handlerAttached = true))
    }

    @Test
    fun `a handler without a messenger cannot serve`() {
        // The background refill engine mounts the handler but never attaches a
        // messenger to it.
        assertFalse(GroupedRequestListener.canServe(messengerAttached = false, handlerAttached = true))
    }

    @Test
    fun `a messenger without a handler cannot serve`() {
        assertFalse(GroupedRequestListener.canServe(messengerAttached = true, handlerAttached = false))
    }

    @Test
    fun `a detached app cannot serve`() {
        assertFalse(GroupedRequestListener.canServe(messengerAttached = false, handlerAttached = false))
    }
}
