import 'package:aves/model/source/tag.dart';
import 'package:aves/services/analysis_service.dart';
import 'package:aves/widgets/aves_app.dart';

/// Whether the analysis service, rather than the in-app worker, should sweep the
/// global catalog backlog.
///
/// The service keeps working with the app in the background, so a backlog big
/// enough to outlast a visit belongs to it. Below the legacy `analyze` threshold
/// the round trip through WorkManager costs more than doing the work in place.
bool shouldDelegateCatalogToService({required bool canUseAnalysisService, required int uncatalogued}) => canUseAnalysisService && uncatalogued > TagMixin.commitCountThreshold;

/// Asks the analysis service to sweep the global backlog from the database.
///
/// The platform rejects a start while the app is in the background, so this
/// skips instead of reporting an error: the next foreground visit re-asks.
Future<void> startPagedAnalysisService() async {
  switch (AvesApp.lifecycleStateNotifier.value) {
    case .resumed:
    case .inactive:
      break;
    default:
      return;
  }
  await AnalysisService.startService(force: false, paged: true);
}

/// Stops the analysis service's sweep, so the app can take the device for the
/// current view before handing the backlog back.
Future<void> cancelPagedAnalysisService() => AnalysisService.cancelService();

/// Whether taking the device back from the analysis service is worth it.
///
/// Preempting costs a WorkManager round trip and, while the service is
/// mid-batch, the rows it has computed but not committed yet — up to
/// `TagMixin.commitCountThreshold`. Below that many uncatalogued rows in the
/// view the trade loses more work than it saves, so the service is left alone
/// and the view's few rows are served alongside it.
bool shouldPreemptCatalogService({required bool serviceDelegated, required int scopedUncatalogued}) => serviceDelegated && scopedUncatalogued >= TagMixin.commitCountThreshold;
