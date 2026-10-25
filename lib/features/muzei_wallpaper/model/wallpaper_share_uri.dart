import 'package:aves/model/entry/entry.dart';

/// The URI to hand to another app for [entry].
///
/// A file URI is preferred: the native side wraps it in the app's read-only
/// FileProvider, so the receiver reads the bytes directly. A MediaStore URI is
/// kept only when no path is known, because some system galleries resolve it
/// through their own stale index and report a perfectly valid image as
/// corrupted.
String wallpaperShareUri(AvesEntry entry) {
  final path = entry.path;
  return path != null && path.isNotEmpty ? Uri.file(path).toString() : entry.uri;
}
