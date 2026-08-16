import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:success_erp/core/services/secret_store.dart';

/// In-memory [SecretStore] that also survives being "restarted", so a cold
/// start can be replayed while the stored refresh token persists — exactly what
/// happens on a real device.
class InMemorySecretStore implements SecretStore {
  final Map<String, String> values;
  bool throwOnRead = false;

  InMemorySecretStore([Map<String, String>? initial])
      : values = {...?initial};

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) throw Exception('keystore locked');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A small but faithful simulation of the Microsoft identity token endpoint plus
/// the Graph workbook/table/row endpoints the app actually calls.
///
/// Enough to exercise the real [OneDriveExcelService] end to end: workbook
/// creation, table creation, header reconciliation, the 0-based-table to
/// 1-based-sheet row conversion, blank-in-place deletes, and throttling.
class FakeGraph {
  FakeGraph({
    this.workbookExists = false,
    this.refreshTokenValid = true,
  });

  static const String itemId = 'ITEM123';

  bool workbookExists;

  /// When false the token endpoint answers `invalid_grant`, i.e. a genuinely
  /// dead session.
  bool refreshTokenValid;

  /// Number of upcoming Graph calls to answer with 429 before succeeding.
  int throttleNextCalls = 0;

  /// Seconds to advertise in `Retry-After` while throttling.
  int retryAfterSeconds = 1;

  /// Fails the next N Graph calls with a 500.
  int failNextCalls = 0;

  /// Answers the next N Graph calls with a 404 — e.g. the workbook was deleted
  /// or moved outside the app.
  int notFoundNextCalls = 0;

  /// Worksheet names present in the workbook.
  final Set<String> worksheets = {};

  /// Table name -> header row.
  final Map<String, List<String>> tableHeaders = {};

  /// Table name -> data rows (each a list of cell strings).
  final Map<String, List<List<String>>> tableRows = {};

  /// Every request path seen, for assertions about what the service did.
  final List<String> requestLog = [];

  int tokenRequests = 0;
  int accessTokenSerial = 0;

  /// Form bodies of every token-endpoint call, for asserting what the auth code
  /// exchange sent (notably the loopback redirect_uri).
  final List<Map<String, String>> tokenBodies = [];

  /// Seeds a workbook that already has every table, as a returning user's would.
  void seedExistingWorkbook(Map<String, List<String>> headersByTable) {
    workbookExists = true;
    for (final entry in headersByTable.entries) {
      worksheets.add(entry.key);
      tableHeaders[entry.key] = List.of(entry.value);
      tableRows.putIfAbsent(entry.key, () => []);
    }
  }

  http.Client get client => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final url = request.url;

    if (url.host == 'login.microsoftonline.com') return _token(request);

    final path = url.path.replaceFirst('/v1.0', '');
    requestLog.add('${request.method} $path');

    if (failNextCalls > 0) {
      failNextCalls--;
      return http.Response('{"error":{"message":"boom"}}', 500);
    }
    if (throttleNextCalls > 0) {
      throttleNextCalls--;
      return http.Response(
        '{"error":{"message":"throttled"}}',
        429,
        headers: {'retry-after': '$retryAfterSeconds'},
      );
    }

    if (notFoundNextCalls > 0) {
      notFoundNextCalls--;
      return http.Response('{"error":{"message":"gone"}}', 404);
    }

    // ── Workbook item ────────────────────────────────────────────────────
    if (path == '/me/drive/special/approot:/ERP_App_Data.xlsx') {
      if (!workbookExists) return http.Response('{}', 404);
      return _ok({'id': itemId, 'name': 'ERP_App_Data.xlsx'});
    }
    if (path == '/me/drive/special/approot:/ERP_App_Data.xlsx:/content') {
      // A real upload must be a valid Office package, not an empty body.
      if (request.bodyBytes.length < 100) {
        return http.Response('{"error":{"message":"not a workbook"}}', 400);
      }
      workbookExists = true;
      worksheets.add('Sheet1');
      return _ok({'id': itemId});
    }

    if (!path.startsWith('/me/drive/items/$itemId/workbook')) {
      return http.Response('{"error":{"message":"unexpected path"}}', 404);
    }
    final wb = path.substring('/me/drive/items/$itemId/workbook'.length);

    // ── Worksheets ───────────────────────────────────────────────────────
    if (wb == '/worksheets' && request.method == 'GET') {
      return _ok({'value': worksheets.map((n) => {'name': n}).toList()});
    }
    if (wb == '/worksheets' && request.method == 'POST') {
      worksheets.add(_body(request)['name'] as String);
      return _ok({'name': _body(request)['name']});
    }
    if (wb.startsWith('/worksheets/') && request.method == 'DELETE') {
      worksheets.remove(wb.split('/')[2]);
      return http.Response('', 204);
    }

    // ── Tables ───────────────────────────────────────────────────────────
    if (wb == '/tables' && request.method == 'GET') {
      return _ok({'value': tableHeaders.keys.map((n) => {'name': n}).toList()});
    }

    final rangeMatch =
        RegExp(r"^/worksheets/([^/]+)/range\(address='([^']+)'\)$").firstMatch(wb);
    if (rangeMatch != null && request.method == 'PATCH') {
      final sheet = rangeMatch.group(1)!;
      final values = (_body(request)['values'] as List).first as List;
      tableHeaders[sheet] = values.map((v) => v.toString()).toList();
      tableRows.putIfAbsent(sheet, () => []);
      return _ok({});
    }

    final addTable =
        RegExp(r'^/worksheets/([^/]+)/tables/add$').firstMatch(wb);
    if (addTable != null) {
      // Graph names new tables Table1, Table2… the service renames them.
      return _ok({'name': 'Table${tableHeaders.length}'});
    }

    final renameTable = RegExp(r'^/tables/([^/]+)$').firstMatch(wb);
    if (renameTable != null && request.method == 'PATCH') {
      return _ok({'name': _body(request)['name']});
    }

    final headerRange =
        RegExp(r'^/tables/([^/]+)/headerRowRange$').firstMatch(wb);
    if (headerRange != null) {
      final table = headerRange.group(1)!;
      return _ok({'values': [tableHeaders[table] ?? []]});
    }

    final resize = RegExp(r'^/tables/([^/]+)/resize$').firstMatch(wb);
    if (resize != null) return _ok({});

    // ── Rows ─────────────────────────────────────────────────────────────
    final rowsPath = RegExp(r'^/tables/([^/]+)/rows$').firstMatch(wb);
    if (rowsPath != null && request.method == 'GET') {
      final rows = tableRows[rowsPath.group(1)!] ?? [];
      return _ok({
        'value': [
          for (var i = 0; i < rows.length; i++)
            {'index': i, 'values': [rows[i]]},
        ],
      });
    }

    final addRow = RegExp(r'^/tables/([^/]+)/rows/add$').firstMatch(wb);
    if (addRow != null) {
      final table = addRow.group(1)!;
      final values = (_body(request)['values'] as List).first as List;
      final rows = tableRows.putIfAbsent(table, () => []);
      rows.add(values.map((v) => v.toString()).toList());
      return _ok({'index': rows.length - 1});
    }

    final itemAt =
        RegExp(r'^/tables/([^/]+)/rows/itemAt\(index=(\d+)\)$').firstMatch(wb);
    if (itemAt != null) {
      final table = itemAt.group(1)!;
      final index = int.parse(itemAt.group(2)!);
      final rows = tableRows[table] ?? [];
      if (index >= rows.length) return http.Response('{}', 404);
      if (request.method == 'GET') {
        return _ok({'values': [rows[index]]});
      }
      if (request.method == 'PATCH') {
        final values = (_body(request)['values'] as List).first as List;
        rows[index] = values.map((v) => v.toString()).toList();
        return _ok({});
      }
      if (request.method == 'DELETE') {
        // The real API shifts rows here. The service must never call this.
        rows.removeAt(index);
        return http.Response('', 204);
      }
    }

    return http.Response('{"error":{"message":"unhandled $wb"}}', 404);
  }

  Future<http.Response> _token(http.Request request) async {
    tokenRequests++;
    final form = Uri.splitQueryString(request.body);
    tokenBodies.add(form);
    if (form['grant_type'] == 'refresh_token' && !refreshTokenValid) {
      return http.Response('{"error":"invalid_grant"}', 400);
    }
    accessTokenSerial++;
    return _ok({
      'access_token': 'ACCESS_$accessTokenSerial',
      'refresh_token': 'REFRESH_$accessTokenSerial',
      'expires_in': 3600,
    });
  }

  static Map<String, dynamic> _body(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  static http.Response _ok(Map<String, dynamic> json) => http.Response(
        jsonEncode(json),
        200,
        headers: {'content-type': 'application/json'},
      );

  /// Rows of [table] as the app would see them, blanks included.
  List<List<String>> rowsOf(String table) => tableRows[table] ?? [];
}
