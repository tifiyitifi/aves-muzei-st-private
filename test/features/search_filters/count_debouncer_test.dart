import 'dart:async';

import 'package:aves/features/search_filters/services/count_debouncer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sheet counts through SQL: rapid edits must not fire one query each, and a
/// slow answer must not land on a newer draft.
void main() {
  testWidgets('rapid edits run one count after the delay', (tester) async {
    var calls = 0;
    final results = <int?>[];
    final debouncer = CountDebouncer(
      delay: const Duration(milliseconds: 300),
      count: () async {
        calls++;
        return calls;
      },
      onResult: results.add,
      isAlive: () => true,
    );
    addTearDown(debouncer.dispose);

    debouncer
      ..schedule()
      ..schedule()
      ..schedule();
    await tester.pump(const Duration(milliseconds: 299));
    expect(calls, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    expect(results, [1]);
  });

  testWidgets('a late answer does not overwrite a newer one', (tester) async {
    final pending = <Completer<int?>>[];
    final results = <int?>[];
    final debouncer = CountDebouncer(
      delay: const Duration(milliseconds: 300),
      count: () {
        final completer = Completer<int?>();
        pending.add(completer);
        return completer.future;
      },
      onResult: results.add,
      isAlive: () => true,
    );
    addTearDown(debouncer.dispose);

    debouncer.schedule();
    await tester.pump(const Duration(milliseconds: 300));
    expect(pending, hasLength(1));

    // A newer draft arrives while the first query is still running.
    debouncer.schedule();
    await tester.pump(const Duration(milliseconds: 300));
    expect(pending, hasLength(2));

    pending[0].complete(1);
    await tester.pump();
    expect(results, isEmpty);

    pending[1].complete(2);
    await tester.pump();
    expect(results, [2]);
  });

  testWidgets('a disposed debouncer runs nothing', (tester) async {
    var calls = 0;
    final results = <int?>[];
    final debouncer = CountDebouncer(
      delay: const Duration(milliseconds: 300),
      count: () async {
        calls++;
        return calls;
      },
      onResult: results.add,
      isAlive: () => true,
    );

    debouncer
      ..schedule()
      ..dispose();
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, 0);
    expect(results, isEmpty);
  });

  testWidgets('an answer for a closed sheet is dropped', (tester) async {
    final results = <int?>[];
    var alive = true;
    final debouncer = CountDebouncer(
      delay: const Duration(milliseconds: 300),
      count: () async => 7,
      onResult: results.add,
      isAlive: () => alive,
    );
    addTearDown(debouncer.dispose);

    debouncer.schedule();
    // The widget is gone by the time the query answers, even though the
    // debouncer itself has not been disposed yet.
    alive = false;
    await tester.pump(const Duration(milliseconds: 300));

    expect(results, isEmpty);
  });
}
