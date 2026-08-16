import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../exceptions/storage_unavailable_exception.dart';
import 'blank_workbook.dart';
import 'microsoft_auth.dart';
import 'storage_backend.dart';
import 'workbook_store.dart';

/// Microsoft OneDrive / Graph implementation of the workbook (AGENTS.md §2).
///
/// A single workbook, `ERP_App_Data.xlsx`, in the app's OneDrive **app folder**
/// (`special/approot`) — not full OneDrive access. Each entity is a real Excel
/// Table, so row reads and writes go through Graph's table/row endpoints rather
/// than raw cell ranges.
class OneDriveExcelService implements WorkbookStore, StorageBackend {
  static const String workbookName = 'ERP_App_Data.xlsx';
  static const String _graph = 'https://graph.microsoft.com/v1.0';

  /// Where the last-known-good workbook layout (item id + per-table headers) is
  /// cached so a normal launch skips the full Graph verification.
  static const String storeCacheKey = 'onedrive_store_cache';

  final MicrosoftAuth _auth;
  final http.Client _http;

  /// Where the layout cache lives. Null disables caching entirely (tests that
  /// exercise a specific setup pass null and always verify).
  final Future<SharedPreferences> Function()? _prefsLoader;

  OneDriveExcelService({
    MicrosoftAuth? auth,
    http.Client? httpClient,
    Future<SharedPreferences> Function()? prefsLoader,
  })  : _auth = auth ?? MicrosoftAuth(),
        _http = httpClient ?? http.Client(),
        _prefsLoader = prefsLoader;

  String? _itemId;

  /// Header row actually present in each table.
  final Map<String, List<String>> _headerCache = {};

  /// Table name as Graph knows it, per entity. Kept so a workbook whose tables
  /// were named differently still works.
  final Map<String, String> _tableNames = {};

  String? get itemId => _itemId;

  // ── StorageBackend ────────────────────────────────────────────────────────

  @override
  bool get isReady => _itemId != null && _headerCache.isNotEmpty;

  @override
  Future<bool> restoreSession() async {
    dev.log('[OneDrive] restoreSession: acquiring token silently');
    try {
      await _auth.acquireTokenSilently();
    } on NoStoredSessionException {
      dev.log('[OneDrive] no stored session');
      await _invalidateCache();
      return false;
    }
    // A normal launch reuses the last verified layout — item id and per-table
    // headers — so the ~13 round-trips of workbook/table reconciliation
    // collapse to zero. Full verification still runs when the cache is absent,
    // its schema version changed, or a call unexpectedly 404s.
    if (await _tryRestoreFromCache()) {
      dev.log('[OneDrive] Ready from local cache; skipping workbook verify');
      return true;
    }
    await _prepareStore();
    return true;
  }

  @override
  Future<void> signIn() async {
    await _auth.signInInteractively();
    await _prepareStore();
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    _itemId = null;
    _headerCache.clear();
    _tableNames.clear();
    await _invalidateCache();
  }

  Future<void> _prepareStore() async {
    try {
      await _ensureWorkbook();
      await _ensureTables();
      await _writeCache();
    } on StorageUnavailableException {
      rethrow;
    } catch (e, st) {
      dev.log('[OneDrive] store preparation failed: $e\n$st');
      throw StorageUnavailableException(_friendlyError(e));
    }
  }

  // ── Local layout cache ─────────────────────────────────────────────────────
  //
  // The workbook's item id and each table's header row can't drift unless the
  // schema changes or the workbook is removed/replaced, so caching them turns a
  // cold start's workbook verification into zero network calls.
  //
  // It is deliberately an optimisation, never a correctness requirement: any
  // cache read/write failure falls back to the full verification path, and any
  // 404 from Graph (workbook/table deleted elsewhere) invalidates it so the
  // next restore rebuilds the layout from scratch.

  Future<bool> _tryRestoreFromCache() async {
    final loader = _prefsLoader;
    if (loader == null) return false;
    try {
      final prefs = await loader();
      final raw = prefs.getString(storeCacheKey);
      if (raw == null) return false;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['schemaVersion'] != WorkbookSchema.version) return false;
      final itemId = json['itemId'] as String?;
      final headers = json['headers'] as Map<String, dynamic>?;
      if (itemId == null || itemId.isEmpty || headers == null) return false;
      for (final entity in WorkbookSchema.tableNames) {
        final header = headers[entity];
        if (header is! List || header.isEmpty) return false;
      }
      _itemId = itemId;
      _headerCache.clear();
      _tableNames.clear();
      for (final entity in WorkbookSchema.tableNames) {
        _headerCache[entity] =
            (headers[entity] as List).map((c) => c.toString()).toList();
        _tableNames[entity] = entity;
      }
      return true;
    } catch (e) {
      dev.log('[OneDrive] store cache unusable; verifying workbook: $e');
      return false;
    }
  }

  Future<void> _writeCache() async {
    final loader = _prefsLoader;
    if (loader == null) return;
    try {
      final prefs = await loader();
      await prefs.setString(
        storeCacheKey,
        jsonEncode({
          'schemaVersion': WorkbookSchema.version,
          'itemId': _itemId,
          'headers': {
            for (final e in _headerCache.entries) e.key: e.value,
          },
        }),
      );
    } catch (e) {
      dev.log('[OneDrive] could not persist store cache: $e');
    }
  }

  Future<void> _invalidateCache() async {
    final loader = _prefsLoader;
    if (loader == null) return;
    try {
      final prefs = await loader();
      await prefs.remove(storeCacheKey);
    } catch (e) {
      dev.log('[OneDrive] could not clear store cache: $e');
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Connection refused') ||
        msg.contains('Connection closed')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (msg.contains('429') || msg.contains('throttl')) {
      return 'OneDrive is rate-limiting us. Try again in a moment.';
    }
    return 'Could not open your ERP workbook on OneDrive. Please try again.';
  }

  // ── HTTP plumbing ─────────────────────────────────────────────────────────

  Future<Map<String, String>> _headers({String? contentType}) async {
    final token = await _auth.acquireTokenSilently();
    final headers = {'Authorization': 'Bearer $token'};
    if (contentType != null) headers['Content-Type'] = contentType;
    return headers;
  }

  /// Sends a Graph request, retrying throttling and one 401 (AGENTS.md §10).
  ///
  /// Graph signals throttling with 429 plus a `Retry-After` header; honouring it
  /// is the documented requirement, so the header wins over our own backoff.
  Future<http.Response> _send(
    String method,
    String path, {
    Object? jsonBody,
    List<int>? rawBody,
    String? contentType,
    bool allowNotFound = false,
  }) async {
    const maxAttempts = 3;
    final uri = Uri.parse('$_graph$path');

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final request = http.Request(method, uri)
        ..headers.addAll(await _headers(
          contentType: contentType ??
              (jsonBody != null ? 'application/json' : null),
        ));
      if (jsonBody != null) {
        request.body = jsonEncode(jsonBody);
      } else if (rawBody != null) {
        request.bodyBytes = rawBody;
      }

      http.Response response;
      try {
        response = await http.Response.fromStream(await _http.send(request));
      } catch (e) {
        if (attempt == maxAttempts - 1) {
          throw StorageUnavailableException(_friendlyError(e));
        }
        await Future.delayed(Duration(seconds: 1 << attempt));
        continue;
      }

      if (response.statusCode == 404 && allowNotFound) return response;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }

      final isLast = attempt == maxAttempts - 1;
      if ((response.statusCode == 429 ||
              response.statusCode == 503 ||
              response.statusCode == 509) &&
          !isLast) {
        final retryAfter =
            int.tryParse(response.headers['retry-after'] ?? '') ?? (1 << attempt);
        dev.log('[OneDrive] ${response.statusCode}; retrying in ${retryAfter}s');
        await Future.delayed(Duration(seconds: retryAfter.clamp(1, 30)));
        continue;
      }
      if (response.statusCode == 401 && !isLast) {
        // Force a refresh on the next _headers() call.
        dev.log('[OneDrive] 401; re-acquiring token');
        await _auth.acquireTokenSilently();
        continue;
      }

      if (response.statusCode == 404) {
        // The workbook or a table was deleted/moved outside the app. The cached
        // layout is stale, so the next restore re-verifies from scratch.
        await _invalidateCache();
      }

      throw StorageUnavailableException(
        'OneDrive returned ${response.statusCode} for $method $path. '
        '${_graphMessage(response.body)}',
      );
    }
    throw const StorageUnavailableException('Try again in a moment.');
  }

  static String _graphMessage(String body) {
    try {
      final error = (jsonDecode(body) as Map<String, dynamic>)['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
    } catch (_) {}
    return '';
  }

  static Map<String, dynamic> _json(http.Response response) =>
      response.body.isEmpty
          ? const {}
          : jsonDecode(response.body) as Map<String, dynamic>;

  // ── Workbook / table setup ────────────────────────────────────────────────

  Future<void> _ensureWorkbook() async {
    final existing = await _send(
      'GET',
      '/me/drive/special/approot:/$workbookName',
      allowNotFound: true,
    );

    if (existing.statusCode == 200) {
      _itemId = _json(existing)['id'] as String?;
      dev.log('[OneDrive] using existing workbook $_itemId');
      return;
    }

    dev.log('[OneDrive] creating $workbookName in the app folder');
    final created = await _send(
      'PUT',
      '/me/drive/special/approot:/$workbookName:/content',
      rawBody: BlankWorkbook.bytes(),
      contentType: BlankWorkbook.mimeType,
    );
    _itemId = _json(created)['id'] as String?;
    if (_itemId == null) {
      throw const StorageUnavailableException(
        'OneDrive did not return an id for the new workbook.',
      );
    }
  }

  String get _workbookPath => '/me/drive/items/$_itemId/workbook';

  Future<void> _ensureTables() async {
    final (worksheets, tables) = await (
      _listNames('$_workbookPath/worksheets'),
      _listNames('$_workbookPath/tables'),
    ).wait;

    _headerCache.clear();
    _tableNames.clear();

    // One Graph round-trip per entity, all in flight at once instead of 10
    // sequential ones. Each entity's worksheet/table work is independent, so
    // the network latency of reconciling one table no longer blocks the others.
    await Future.wait([
      for (final entity in WorkbookSchema.tableNames)
        _ensureTable(entity, worksheets.contains(entity), tables.contains(entity)),
    ]);

    // The placeholder sheet from the freshly created package is no longer
    // needed once real worksheets exist. Failing to remove it is harmless.
    if (worksheets.contains(BlankWorkbook.placeholderSheet) &&
        !WorkbookSchema.tableNames.contains(BlankWorkbook.placeholderSheet)) {
      try {
        await _send('DELETE',
            '$_workbookPath/worksheets/${BlankWorkbook.placeholderSheet}');
      } catch (e) {
        dev.log('[OneDrive] could not delete placeholder sheet: $e');
      }
    }
  }

  Future<void> _ensureTable(
    String entity,
    bool worksheetExists,
    bool tableExists,
  ) async {
    final headers = WorkbookSchema.headersOf(entity);

    if (!worksheetExists) {
      await _send('POST', '$_workbookPath/worksheets',
          jsonBody: {'name': entity});
    }

    if (!tableExists) {
      _headerCache[entity] = await _createTable(entity, headers);
    } else {
      _tableNames[entity] = entity;
      _headerCache[entity] = await _reconcileHeader(entity, headers);
    }
  }

  Future<Set<String>> _listNames(String path) async {
    final response = await _send('GET', '$path?\$select=name');
    final values = _json(response)['value'];
    if (values is! List) return {};
    return values
        .map((v) => (v as Map<String, dynamic>)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
  }

  /// Writes the header row, then promotes it to a real Excel Table so the
  /// table/row endpoints can be used (AGENTS.md §2).
  Future<List<String>> _createTable(String entity, List<String> headers) async {
    final address = 'A1:${_columnLetter(headers.length - 1)}1';
    await _send(
      'PATCH',
      "$_workbookPath/worksheets/$entity/range(address='$address')",
      jsonBody: {'values': [headers]},
    );
    final created = await _send(
      'POST',
      '$_workbookPath/worksheets/$entity/tables/add',
      jsonBody: {'address': address, 'hasHeaders': true},
    );
    final createdName = _json(created)['name'] as String?;
    if (createdName != null && createdName != entity) {
      // Graph names new tables Table1, Table2… Rename so lookups are by entity.
      await _send('PATCH', '$_workbookPath/tables/$createdName',
          jsonBody: {'name': entity});
    }
    _tableNames[entity] = entity;
    dev.log('[OneDrive] created table $entity');
    return List<String>.from(headers);
  }

  /// Appends any canonical columns the table is missing to the END of its header
  /// row, so existing data never shifts.
  Future<List<String>> _reconcileHeader(
    String entity,
    List<String> canonical,
  ) async {
    final response =
        await _send('GET', '$_workbookPath/tables/$entity/headerRowRange');
    final values = _json(response)['values'];
    final current = (values is List && values.isNotEmpty)
        ? (values.first as List)
            .map((c) => c?.toString().trim() ?? '')
            .where((c) => c.isNotEmpty)
            .toList()
        : <String>[];

    if (current.isEmpty) return List<String>.from(canonical);

    final missing = canonical.where((c) => !current.contains(c)).toList();
    if (missing.isEmpty) return current;

    final merged = [...current, ...missing];
    // Resizing the table to cover the new columns, then writing the header.
    await _send(
      'PATCH',
      "$_workbookPath/worksheets/$entity/range(address='A1:${_columnLetter(merged.length - 1)}1')",
      jsonBody: {'values': [merged]},
    );
    await _send(
      'POST',
      '$_workbookPath/tables/$entity/resize',
      jsonBody: {
        'address': 'A1:${_columnLetter(merged.length - 1)}'
            '${await _tableRowCount(entity) + 1}',
      },
    );
    dev.log('[OneDrive] $entity: appended columns ${missing.join(", ")}');
    return merged;
  }

  Future<int> _tableRowCount(String entity) async {
    final response =
        await _send('GET', '$_workbookPath/tables/$entity/rows?\$select=index');
    final values = _json(response)['value'];
    return values is List ? values.length : 0;
  }

  static String _columnLetter(int index) {
    var result = '';
    var i = index;
    while (i >= 0) {
      result = String.fromCharCode((i % 26) + 65) + result;
      i = (i ~/ 26) - 1;
    }
    return result;
  }

  // ── WorkbookStore ─────────────────────────────────────────────────────────

  @override
  List<String> headersFor(String table) =>
      _headerCache[table] ?? WorkbookSchema.headersOf(table);

  /// Graph table rows are 0-based and exclude the header; the store contract is
  /// 1-based including the header. This is the only place that conversion lives.
  static int _toTableIndex(int sheetRowIndex) => sheetRowIndex - 2;
  static int _toSheetRow(int tableIndex) => tableIndex + 2;

  List<String> _toValues(String table, Map<String, String> row) {
    final headers = headersFor(table);
    return [for (final h in headers) row[h] ?? ''];
  }

  Map<String, String> _toMap(String table, List<Object?> raw) {
    final headers = headersFor(table);
    return {
      for (var i = 0; i < headers.length; i++)
        headers[i]: i < raw.length ? (raw[i]?.toString() ?? '') : '',
    };
  }

  @override
  Future<List<Map<String, String>>> getAllRows(String table) async {
    final response = await _send(
      'GET',
      '$_workbookPath/tables/$table/rows?\$select=index,values',
    );
    final values = _json(response)['value'];
    if (values is! List) return [];

    // Graph normally returns rows in index order, but sort defensively: the
    // whole id→row index depends on positional stability.
    final rows = values
        .map((v) => v as Map<String, dynamic>)
        .toList()
      ..sort((a, b) =>
          ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));

    return rows.map((row) {
      final cells = row['values'];
      final firstRow = (cells is List && cells.isNotEmpty) ? cells.first : null;
      return _toMap(table, firstRow is List ? firstRow : const []);
    }).toList();
  }

  @override
  Future<Map<String, String>> getRow(String table, int rowIndex) async {
    final index = _toTableIndex(rowIndex);
    if (index < 0) return _toMap(table, const []);
    final response = await _send(
      'GET',
      '$_workbookPath/tables/$table/rows/itemAt(index=$index)',
      allowNotFound: true,
    );
    if (response.statusCode == 404) return _toMap(table, const []);
    final cells = _json(response)['values'];
    final firstRow = (cells is List && cells.isNotEmpty) ? cells.first : null;
    return _toMap(table, firstRow is List ? firstRow : const []);
  }

  @override
  Future<int> appendRow(String table, Map<String, String> row) async {
    final response = await _send(
      'POST',
      '$_workbookPath/tables/$table/rows/add',
      jsonBody: {'values': [_toValues(table, row)]},
    );
    final index = (_json(response)['index'] as num?)?.toInt();
    if (index != null) return _toSheetRow(index);
    // Graph omitted the index; fall back to the row count.
    final count = await _tableRowCount(table);
    return _toSheetRow(count - 1);
  }

  @override
  Future<void> updateRow(
    String table,
    int rowIndex,
    Map<String, String> row,
  ) async {
    final index = _toTableIndex(rowIndex);
    if (index < 0) return;
    await _send(
      'PATCH',
      '$_workbookPath/tables/$table/rows/itemAt(index=$index)',
      jsonBody: {'values': [_toValues(table, row)]},
    );
  }

  /// Blanks the row rather than deleting it.
  ///
  /// Graph's `DELETE .../rows/itemAt(index=n)` physically removes the row and
  /// SHIFTS every row after it up by one, which would silently invalidate the
  /// id→row index a bulk delete captured up front. Writing empty values keeps
  /// positions stable, honouring the [WorkbookStore] deletion contract.
  @override
  Future<void> clearRow(String table, int rowIndex) async {
    final index = _toTableIndex(rowIndex);
    if (index < 0) return;
    final blanks = [for (final _ in headersFor(table)) ''];
    await _send(
      'PATCH',
      '$_workbookPath/tables/$table/rows/itemAt(index=$index)',
      jsonBody: {'values': [blanks]},
    );
  }
}
