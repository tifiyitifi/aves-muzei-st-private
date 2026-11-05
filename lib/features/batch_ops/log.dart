import 'package:aves/features/logging/log.dart';

/// Log channel owned by the batch engine (never a shared catch-all).
const String batchOpsLogKey = 'log.batch_ops';

/// Channels this feature owns, opened in debug builds by `Log.init`.
const List<String> batchOpsDebugLogKeys = [batchOpsLogKey];

const AreaKeyLog batchLog = AreaKeyLog(batchOpsLogKey);
