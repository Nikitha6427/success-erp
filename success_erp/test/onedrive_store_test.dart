import 'package:flutter_test/flutter_test.dart';
import 'package:success_erp/core/exceptions/storage_unavailable_exception.dart';
import 'package:success_erp/core/services/blank_workbook.dart';
import 'package:success_erp/core/services/microsoft_auth.dart';
import 'package:success_erp/core/services/onedrive_excel_service.dart';
import 'package:success_erp/core/services/workbook_store.dart';

import 'fake_graph.dart';

late FakeGraph graph;
late InMemorySecretStore secrets;

OneDriveExcelService buildService() => OneDriveExcelService(
      httpClient: graph.client,
      auth: MicrosoftAuth(
        httpClient: graph.client,
        secrets: secrets,
        clientId: 'TEST_CLIENT_ID',
        interactiveSignIn: (url, scheme) async =>
            '$scheme://auth?code=CODE&state=${Uri.parse(url).queryParameters['state']}',
      ),
    );

void main() {
  setUp(() {
    graph = FakeGraph();
    secrets = InMemorySecretStore({'ms_refresh_token': 'STORED_REFRESH'});
  });

  group('workbook setup', () {
    test('creates ERP_App_Data.xlsx in the app folder on first run', () async {
      final service = buildService();

      expect(await service.restoreSession(), isTrue);

      expect(service.isReady, isTrue);
      expect(graph.workbookExists, isTrue);
      expect(
        graph.requestLog,
        contains('PUT /me/drive/special/approot:/ERP_App_Data.xlsx:/content'),
      );
      // App folder only, never the whole drive (AGENTS.md §2).
      expect(
        graph.requestLog.every((r) => !r.contains('/me/drive/root')),
        isTrue,
      );
    });

    test('the uploaded file is a real Office package, not an empty blob', () {
      final bytes = BlankWorkbook.bytes();
      // A zip local-file header, and big enough for Graph to accept.
      expect(bytes.sublist(0, 2), [0x50, 0x4B]);
      expect(bytes.length, greaterThan(100));
    });

    test('creates a worksheet and a real Excel Table per entity', () async {
      await buildService().restoreSession();

      for (final entity in WorkbookSchema.tableNames) {
        expect(graph.worksheets, contains(entity),
            reason: '$entity worksheet missing');
        expect(graph.tableHeaders[entity], WorkbookSchema.headersOf(entity),
            reason: '$entity table header wrong');
        expect(
          graph.requestLog,
          contains('POST /me/drive/items/${FakeGraph.itemId}/workbook'
              '/worksheets/$entity/tables/add'),
          reason: '$entity was not promoted to a table',
        );
      }
    });

    test('removes the placeholder sheet once real worksheets exist', () async {
      await buildService().restoreSession();
      expect(graph.worksheets, isNot(contains(BlankWorkbook.placeholderSheet)));
    });

    test('reuses an existing workbook without recreating it', () async {
      graph.seedExistingWorkbook({
        for (final t in WorkbookSchema.tableNames) t: WorkbookSchema.headersOf(t),
      });

      await buildService().restoreSession();

      expect(
        graph.requestLog.any((r) => r.startsWith('PUT ')),
        isFalse,
        reason: 'should not have re-uploaded the workbook',
      );
      expect(
        graph.requestLog.any((r) => r.contains('/tables/add')),
        isFalse,
        reason: 'should not have recreated tables',
      );
    });

    test('appends missing columns to an older workbook without shifting data',
        () async {
      // A workbook written before `remarks` and `updated_at` existed.
      graph.seedExistingWorkbook({
        for (final t in WorkbookSchema.tableNames) t: WorkbookSchema.headersOf(t),
      });
      graph.tableHeaders['PurchaseOrderItems'] = [
        'po_item_id', 'po_id', 'product_id', 'quantity', 'rate',
        'delivered_qty', 'pending_qty',
      ];
      graph.tableRows['PurchaseOrderItems'] = [
        ['i1', 'po1', 'p1', '10', '250', '4', '6'],
      ];

      final service = buildService();
      await service.restoreSession();

      final headers = service.headersFor('PurchaseOrderItems');
      // Original columns keep their positions; new ones are appended.
      expect(headers.sublist(0, 7), [
        'po_item_id', 'po_id', 'product_id', 'quantity', 'rate',
        'delivered_qty', 'pending_qty',
      ]);
      expect(headers, containsAll(['remarks', 'updated_at']));

      final rows = await service.getAllRows('PurchaseOrderItems');
      expect(rows.single['quantity'], '10');
      expect(rows.single['pending_qty'], '6');
      expect(rows.single['remarks'], '');
    });
  });

  group('row addressing', () {
    late OneDriveExcelService service;

    setUp(() async {
      service = buildService();
      await service.restoreSession();
    });

    test('appendRow returns a 1-based sheet row, header at row 1', () async {
      // Graph table index 0 is the first data row, which is sheet row 2.
      expect(await service.appendRow('Customers', {'customer_id': 'a'}), 2);
      expect(await service.appendRow('Customers', {'customer_id': 'b'}), 3);
      expect(await service.appendRow('Customers', {'customer_id': 'c'}), 4);
    });

    test('getRow reads the row the sheet index names', () async {
      await service.appendRow('Customers', {'customer_id': 'a', 'name': 'Ann'});
      await service.appendRow('Customers', {'customer_id': 'b', 'name': 'Bob'});

      expect((await service.getRow('Customers', 2))['name'], 'Ann');
      expect((await service.getRow('Customers', 3))['name'], 'Bob');
    });

    test('updateRow writes the row the sheet index names', () async {
      await service.appendRow('Customers', {'customer_id': 'a', 'name': 'Ann'});
      await service.appendRow('Customers', {'customer_id': 'b', 'name': 'Bob'});

      await service
          .updateRow('Customers', 3, {'customer_id': 'b', 'name': 'Bobby'});

      final rows = await service.getAllRows('Customers');
      expect(rows[0]['name'], 'Ann');
      expect(rows[1]['name'], 'Bobby');
    });

    test('the header row itself is never addressable', () async {
      await service.appendRow('Customers', {'customer_id': 'a'});
      // Sheet row 1 is the header; the store contract makes it unreachable, so
      // a read yields blanks and a write is a no-op rather than corrupting the
      // header row.
      final headerRead = await service.getRow('Customers', 1);
      expect(headerRead.values.every((v) => v.isEmpty), isTrue);

      await service.updateRow('Customers', 1, {'customer_id': 'HACK'});
      expect(graph.tableHeaders['Customers'],
          WorkbookSchema.headersOf('Customers'));
      expect((await service.getAllRows('Customers')).single['customer_id'], 'a');
    });

    test('values are written by column name, not position', () async {
      await service.appendRow('Invoices', {
        'invoice_id': 'inv1',
        'total_amount': '590.00',
        'status': 'Paid',
      });
      final row = (await service.getAllRows('Invoices')).single;
      expect(row['invoice_id'], 'inv1');
      expect(row['total_amount'], '590.00');
      expect(row['status'], 'Paid');
      expect(row['cgst_amount'], '');
    });

    test('rows are returned in index order even if Graph reorders them',
        () async {
      await service.appendRow('Customers', {'customer_id': 'a'});
      await service.appendRow('Customers', {'customer_id': 'b'});
      await service.appendRow('Customers', {'customer_id': 'c'});

      final rows = await service.getAllRows('Customers');
      expect(rows.map((r) => r['customer_id']), ['a', 'b', 'c']);
    });
  });

  group('deletion blanks the row in place', () {
    late OneDriveExcelService service;

    setUp(() async {
      service = buildService();
      await service.restoreSession();
      await service.appendRow('Customers', {'customer_id': 'a', 'name': 'Ann'});
      await service.appendRow('Customers', {'customer_id': 'b', 'name': 'Bob'});
      await service.appendRow('Customers', {'customer_id': 'c', 'name': 'Cat'});
    });

    test('never calls the row-DELETE endpoint, which would shift rows', () async {
      await service.clearRow('Customers', 3);

      expect(
        graph.requestLog.any((r) => r.startsWith('DELETE') && r.contains('rows')),
        isFalse,
        reason: 'DELETE rows/itemAt shifts every later row up by one, which '
            'would silently invalidate the id -> row index mid-batch',
      );
    });

    test('surviving rows keep their sheet indices', () async {
      await service.clearRow('Customers', 3); // Bob

      // Ann and Cat must still be at rows 2 and 4.
      expect((await service.getRow('Customers', 2))['name'], 'Ann');
      expect((await service.getRow('Customers', 4))['name'], 'Cat');

      final rows = await service.getAllRows('Customers');
      expect(rows, hasLength(3));
      expect(rows[1].values.every((v) => v.isEmpty), isTrue,
          reason: 'the deleted row must read back as blank, not vanish');
    });

    test('several deletions in a batch stay consistent', () async {
      await service.clearRow('Customers', 2);
      await service.clearRow('Customers', 4);

      final rows = await service.getAllRows('Customers');
      expect(rows, hasLength(3));
      expect(rows[0].values.every((v) => v.isEmpty), isTrue);
      expect(rows[1]['name'], 'Bob');
      expect(rows[2].values.every((v) => v.isEmpty), isTrue);
    });
  });

  group('error handling (AGENTS.md §10)', () {
    test('honours Retry-After on throttling and then succeeds', () async {
      graph.seedExistingWorkbook({
        for (final t in WorkbookSchema.tableNames) t: WorkbookSchema.headersOf(t),
      });
      final service = buildService();
      await service.restoreSession();

      graph.throttleNextCalls = 1;
      graph.retryAfterSeconds = 1;

      // Completes despite the 429 rather than surfacing an error.
      expect(await service.appendRow('Customers', {'customer_id': 'a'}), 2);
    });

    test('a persistent server error surfaces as StorageUnavailable', () async {
      graph.failNextCalls = 99;
      final service = buildService();

      await expectLater(
        service.restoreSession(),
        throwsA(isA<StorageUnavailableException>()),
      );
      expect(service.isReady, isFalse);
    });
  });
}
