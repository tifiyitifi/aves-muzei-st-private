import 'dart:io';
import 'dart:ui' as ui;

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Decodes a baked slot file whose path is reused for different artworks.
///
/// `FileImage`, which `Image.file` uses, keys Flutter's image cache by path
/// only. The controller reuses `slots/<id>/sharp.png` whenever it bakes the
/// next artwork into that slot, so a path-keyed image keeps painting the first
/// decode of that path forever. The native renderer re-reads `state.json` and
/// decodes again on every reload, so the page and the desktop drift apart and
/// the page ends up cycling through the first two decoded slots.
///
/// [contentKey] is part of the cache key, so a new artwork in the same slot
/// resolves to a new cache entry.
@immutable
class SlotArtworkImage extends ImageProvider<SlotArtworkImageKey> with Equatable {
  /// The baked file, as stored in `state.json` and resolved by the controller.
  final File file;

  /// Identity of the baked content.
  ///
  /// The sharp PNG is a function of the entry and the target size, so the entry
  /// id is enough: it changes exactly when the slot starts holding another
  /// artwork, which is the case a path-keyed cache gets wrong.
  final int contentKey;

  final double scale;

  const new({
    required this.file,
    required this.contentKey,
    this.scale = 1.0,
  });

  @override
  Future<SlotArtworkImageKey> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<SlotArtworkImageKey>(
      SlotArtworkImageKey(path: file.path, contentKey: contentKey, scale: scale),
    );
  }

  @override
  ImageStreamCompleter loadImage(SlotArtworkImageKey key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.path,
      informationCollector: () sync* {
        yield ErrorDescription('path=${key.path}, contentKey=${key.contentKey}');
      },
    );
  }

  Future<ui.Codec> _loadAsync(SlotArtworkImageKey key, ImageDecoderCallback decode) async {
    final file = File(key.path);
    if (!await file.exists()) {
      throw StateError('the baked wallpaper file is missing: ${key.path}');
    }
    final bytes = await file.readAsBytes();
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  // A widget rebuild must not re-resolve the stream when the artwork is
  // unchanged; the key class already carries the same identity.
  @override
  List<Object?> get props => [file.path, contentKey, scale];
}

/// Cache key of [SlotArtworkImage]: the file path plus the artwork it holds.
@immutable
class SlotArtworkImageKey with Equatable {
  final String path;
  final int contentKey;
  final double scale;

  const new({
    required this.path,
    required this.contentKey,
    required this.scale,
  });

  @override
  List<Object?> get props => [path, contentKey, scale];
}
