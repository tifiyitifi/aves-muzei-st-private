import 'dart:async';

import 'package:aves/features/collection_paging/view/collection_view_hooks.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/widgets/common/behaviour/pop/scope.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:provider/provider.dart';

final DoubleBackPopHandler doubleBackPopHandler = DoubleBackPopHandler._private();

class DoubleBackPopHandler extends PopHandler {
  bool _backOnce = false;
  Timer? _backTimer;

  new _private();

  @override
  bool canPop(BuildContext context) {
    // A borrowed view is not the app's root: backing out of it returns to the
    // page that opened it instead of exiting the app.
    if (CollectionViewHooksScope.maybeOf(context)?.suppressDoubleBack ?? false) return true;
    if (context.select<Settings, bool>((v) => !v.mustBackTwiceToExit)) return true;
    if (Navigator.canPop(context)) return true;
    return false;
  }

  @override
  void onPopBlocked(BuildContext context) {
    if (_backOnce) {
      if (Navigator.canPop(context)) {
        Navigator.maybeOf(context)?.pop();
      } else {
        // exit
        reportService.log('Exit by pop');
        PopExitNotification().dispatch(context);
        SystemNavigator.pop();
      }
    } else {
      _backOnce = true;
      _backTimer?.cancel();
      _backTimer = Timer(ADurations.doubleBackTimerDelay, () => _backOnce = false);
      toast(
        context.l10n.doubleBackExitMessage,
        duration: ADurations.doubleBackTimerDelay,
      );
    }
  }
}
