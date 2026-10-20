import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared state of the first import: the app bar and the one-time explainer
/// read it, so it has to be right while the total is still unknown and to settle
/// exactly once.
void main() {
  late PagedImportStatus status;

  setUp(() => status = PagedImportStatus());
  tearDown(() => status.dispose());

  test('reports progress and keeps the denominator when it lands late', () {
    status.begin();
    expect(status.active, isTrue);
    expect(status.total, 0);

    status.update(250);
    expect(status.done, 250);
    expect(status.total, 0);

    // The platform count arrives after the first batch: the next tick carries
    // it instead of dropping back to "unknown".
    status.update(500, total: 32750);
    expect(status.total, 32750);
    status.update(750);
    expect(status.total, 32750);
    expect(status.done, 750);
  });

  test('ends once and stops notifying afterwards', () {
    var notifications = 0;
    status.addListener(() => notifications++);

    status.begin();
    status.update(100, total: 200);
    expect(notifications, 2);

    status.end();
    expect(status.active, isFalse);
    final afterEnd = notifications;
    status.end();
    expect(notifications, afterEnd);
  });

  test('raises the explainer once until a surface takes it', () {
    status.requestExplainer();
    expect(status.explainerPending, isTrue);

    status.requestExplainer();
    expect(status.explainerPending, isTrue);

    status.clearExplainer();
    expect(status.explainerPending, isFalse);

    // Cleared means answered: nothing re-raises it on its own.
    expect(status.explainerPending, isFalse);
  });
}
