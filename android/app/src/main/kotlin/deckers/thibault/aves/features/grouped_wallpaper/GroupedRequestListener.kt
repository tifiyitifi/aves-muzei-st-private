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
 * The single rule for "can the app serve a wallpaper request right now".
 *
 * Two independent facts have to agree: a channel has to exist to send on, and a
 * Dart handler has to be listening on it. The grouped wallpaper used to check
 * them in two different places with different rules, so the app engine said "not
 * listening", the worker was told "the page is listening", and a tap fell in the
 * gap between them.
 *
 * The handler flag alone is not enough: the background refill engine also mounts
 * a `GroupedWallpaperHandler` and runs the same Dart `attach()`, but it is never
 * given a messenger, so nothing can be delivered to it.
 */
object GroupedRequestListener {
    fun canServe(messengerAttached: Boolean, handlerAttached: Boolean): Boolean = messengerAttached && handlerAttached
}
