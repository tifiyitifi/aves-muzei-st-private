import 'package:aves/features/logging/log.dart';

/// Log channel owned by the browse-only surface (never a shared catch-all).
///
/// The browser reads the media store while the collection is still being
/// organized, so its failures must be separable from the paging engine's.
const String browseOnlyLogKey = 'log.browse_only';

/// Channels this feature owns, opened in debug builds by `Log.init`.
const List<String> browseOnlyDebugLogKeys = [browseOnlyLogKey];

const AreaKeyLog browseOnlyLog = AreaKeyLog(browseOnlyLogKey);
