import 'package:aves/features/logging/log.dart';

/// Log channel owned by the copy-first editor (never a shared catch-all).
const String refraEditLogKey = 'log.refra_edit';

/// Channels this feature owns, opened in debug builds by `Log.init`.
const List<String> refraEditDebugLogKeys = [refraEditLogKey];

const AreaKeyLog refraEditLog = AreaKeyLog(refraEditLogKey);
