import 'package:flutter_test/flutter_test.dart';
import 'package:success_erp/core/services/counter_helper.dart';

import 'fake_workbook_store.dart';

void main() {
  group('Indian financial year (AGENTS.md §4)', () {
    test('April starts a new FY', () {
      expect(CounterHelper.financialYearFor(DateTime(2026, 4, 1)), '2026-27');
      expect(CounterHelper.financialYearFor(DateTime(2026, 12, 31)), '2026-27');
    });

    test('January to March still belong to the previous FY', () {
      expect(CounterHelper.financialYearFor(DateTime(2027, 1, 15)), '2026-27');
      expect(CounterHelper.financialYearFor(DateTime(2027, 3, 31)), '2026-27');
    });

    test('the next April rolls over', () {
      expect(CounterHelper.financialYearFor(DateTime(2027, 4, 1)), '2027-28');
    });

    test('century rollover keeps a two-digit suffix', () {
      expect(CounterHelper.financialYearFor(DateTime(1999, 6, 1)), '1999-00');
      expect(CounterHelper.financialYearFor(DateTime(2000, 6, 1)), '2000-01');
    });
  });

  group('PO numbering (AGENTS.md §4)', () {
    late FakeWorkbookStore store;
    late CounterHelper counter;

    setUp(() {
      store = FakeWorkbookStore();
      counter = CounterHelper(store);
    });

    test('formats as PO/{S|L}{FY}/{sequence}', () async {
      final first = await counter.nextPoNumber(
        category: 'Sales',
        orderDate: DateTime(2026, 5, 4),
      );
      expect(first, 'PO/S2026-27/1');

      final labour = await counter.nextPoNumber(
        category: 'Labour',
        orderDate: DateTime(2026, 5, 4),
      );
      expect(labour, 'PO/L2026-27/1');
    });

    test('category and financial year each get an independent sequence',
        () async {
      for (var i = 0; i < 3; i++) {
        await counter.nextPoNumber(
          category: 'Sales',
          orderDate: DateTime(2026, 5, 4),
        );
      }
      expect(
        await counter.nextPoNumber(
          category: 'Sales',
          orderDate: DateTime(2026, 5, 4),
        ),
        'PO/S2026-27/4',
      );

      // Labour is untouched by the Sales runs.
      expect(
        await counter.nextPoNumber(
          category: 'Labour',
          orderDate: DateTime(2027, 1, 9),
        ),
        'PO/L2026-27/1',
      );

      // A new FY restarts at 1.
      expect(
        await counter.nextPoNumber(
          category: 'Sales',
          orderDate: DateTime(2027, 4, 2),
        ),
        'PO/S2027-28/1',
      );

      // ...and the old FY continues from where it left off.
      expect(
        await counter.nextPoNumber(
          category: 'Sales',
          orderDate: DateTime(2027, 3, 30),
        ),
        'PO/S2026-27/5',
      );
    });

    test('a Jan-March order date uses the previous FY sequence', () async {
      await counter.nextPoNumber(
        category: 'Sales',
        orderDate: DateTime(2026, 11, 1),
      );
      expect(
        await counter.nextPoNumber(
          category: 'Sales',
          orderDate: DateTime(2027, 2, 14),
        ),
        'PO/S2026-27/2',
      );
    });

    test('counter rows carry the compound key', () async {
      await counter.nextPoNumber(
        category: 'Sales',
        orderDate: DateTime(2026, 5, 4),
      );
      expect(store.tables['Counters']!.single, {
        'entity_name': 'PurchaseOrder',
        'category': 'Sales',
        'financial_year': '2026-27',
        'last_number': '1',
      });
    });
  });

  group('simple sequences', () {
    test('pad to four digits and stay independent per entity', () async {
      final counter = CounterHelper(FakeWorkbookStore());
      expect(await counter.nextSimpleNumber('Customer', 'CUST'), 'CUST-0001');
      expect(await counter.nextSimpleNumber('Customer', 'CUST'), 'CUST-0002');
      expect(await counter.nextSimpleNumber('Invoice', 'INV'), 'INV-0001');
      expect(await counter.nextSimpleNumber('DeliveryNote', 'DN'), 'DN-0001');
      expect(await counter.nextSimpleNumber('Customer', 'CUST'), 'CUST-0003');
    });
  });
}
