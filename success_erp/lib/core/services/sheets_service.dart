import 'dart:async';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis/drive/v3.dart';

class AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  final Map<String, String> _headers;

  AuthenticatedClient(this._inner, this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}

class SheetsService {
  // TODO: Replace with your Web OAuth client ID from Google Cloud Console.
  // Create one at: Console > APIs & Services > Credentials > Create Credentials > OAuth client ID > Web application
  static const String _webClientId = '396207157251-8k2ck17pp6d3s5so7pede1jtobr0m33f.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/drive.file'],
    clientId: _webClientId,
  );

  GoogleSignInAccount? _currentUser;
  SheetsApi? _sheetsApi;
  DriveApi? _driveApi;
  String? _spreadsheetId;
  final Map<String, int> _sheetNameToId = {};

  GoogleSignInAccount? get currentUser => _currentUser;
  String? get spreadsheetId => _spreadsheetId;

  static const Map<String, List<String>> tabHeaders = {
    'Customers': [
      'customer_id', 'name', 'phone', 'email', 'address',
      'gst_number', 'tin_number', 'cst_number', 'created_at', 'updated_at', 'customer_code',
    ],
    'Products': [
      'product_id', 'name', 'part_no', 'unit', 'price',
      'tax_percent', 'created_at', 'updated_at', 'hsn_code', 'product_code', 'category',
    ],
    'PurchaseOrders': [
      'po_id', 'po_number', 'customer_id', 'order_date',
      'status', 'created_at', 'updated_at',
    ],
    'PurchaseOrderItems': [
      'po_item_id', 'po_id', 'product_id', 'quantity', 'rate',
      'delivered_qty', 'pending_qty', 'updated_at',
    ],
    'DeliveryNotes': [
      'dn_id', 'dn_number', 'po_id', 'delivery_date', 'created_at',
    ],
    'DeliveryNoteItems': [
      'dn_item_id', 'dn_id', 'po_item_id', 'delivered_qty', 'remark',
    ],
    'Invoices': [
      'invoice_id', 'invoice_number', 'po_id', 'invoice_date',
      'total_amount', 'tax_amount', 'status', 'vehicle_details', 'gst_details',
      'cgst_percent', 'sgst_percent', 'delivery_note_refs', 'po_refs',
    ],
    'InvoiceItems': [
      'invoice_item_id', 'invoice_id', 'product_id', 'quantity',
      'rate', 'tax_percent', 'amount', 'remark',
    ],
    'Counters': [
      'entity_name', 'last_number',
    ],
    'CompanyProfile': [
      'company_id', 'company_name', 'address', 'phone',
      'gst_number', 'state', 'updated_at',
    ],
  };

  Future<void> initialize() async {
    _currentUser = await _googleSignIn.signIn();
    if (_currentUser == null) throw Exception('Sign in cancelled');

    await _createClient();
    await _setupSpreadsheet();
  }

  Future<void> _createClient() async {
    final authHeaders = await _currentUser!.authHeaders;
    final client = AuthenticatedClient(http.Client(), authHeaders);
    _sheetsApi = SheetsApi(client);
    _driveApi = DriveApi(client);
  }

  /// Attempt to silently re-authenticate. Returns true if successful.
  Future<bool> trySilentReAuth() async {
    try {
      dev.log('[Sheets] signInSilently() called');
      final account = await _googleSignIn.signInSilently();
      dev.log('[Sheets] signInSilently() returned: ${account != null ? account.email : "null"}');
      if (account == null) return false;
      _currentUser = account;
      await _createClient();
      return true;
    } catch (e) {
      dev.log('[Sheets] Silent re-auth EXCEPTION: $e');
      return false;
    }
  }

  /// Fallback: try explicit sign-in (shows account picker popup on desktop).
  /// This is called when signInSilently() fails but we know the user has
  /// previously authenticated (via SharedPreferences flag).
  Future<bool> tryExplicitReAuth() async {
    try {
      dev.log('[Sheets] signIn() fallback called');
      final account = await _googleSignIn.signIn();
      dev.log('[Sheets] signIn() fallback returned: ${account != null ? account.email : "null"}');
      if (account == null) return false;
      _currentUser = account;
      await _createClient();
      return true;
    } catch (e) {
      dev.log('[Sheets] Explicit re-auth EXCEPTION: $e');
      return false;
    }
  }

  Future<T> _withRetry<T>(Future<T> Function() operation) async {
    const maxRetries = 3;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await operation();
      } on DetailedApiRequestError catch (e) {
        if (e.status == 429 && attempt < maxRetries - 1) {
          // Rate limited — exponential backoff
          final delay = Duration(seconds: (1 << attempt) * 2);
          dev.log('Rate limited, retrying in ${delay.inSeconds}s (attempt ${attempt + 1})');
          await Future.delayed(delay);
          continue;
        }
        if (e.status == 401 && attempt < maxRetries - 1) {
          // Token expired — try silent re-auth
          dev.log('Token expired, attempting silent re-auth');
          final reAuthed = await trySilentReAuth();
          if (reAuthed) continue;
        }
        rethrow;
      }
    }
    throw Exception('Max retries exceeded');
  }

  Future<void> _setupSpreadsheet() async {
    final response = await _withRetry(() => _driveApi!.files.list(
      q: "name='ERP_App_Data' and mimeType='application/vnd.google-apps.spreadsheet'",
      spaces: 'drive',
    ));

    if (response.files != null && response.files!.isNotEmpty) {
      _spreadsheetId = response.files!.first.id!;
      dev.log('Found existing spreadsheet: $_spreadsheetId');
    } else {
      final spreadsheet = await _withRetry(() => _sheetsApi!.spreadsheets.create(
        Spreadsheet(properties: SpreadsheetProperties(title: 'ERP_App_Data')),
      ));
      _spreadsheetId = spreadsheet.spreadsheetId;
      dev.log('Created new spreadsheet: $_spreadsheetId');
    }

    await _ensureTabsAndHeaders();
  }

  String _columnLetter(int index) {
    String result = '';
    int i = index;
    while (i >= 0) {
      result = String.fromCharCode((i % 26) + 65) + result;
      i = (i ~/ 26) - 1;
    }
    return result;
  }

  Future<void> _ensureTabsAndHeaders() async {
    final spreadsheet = await _withRetry(() => _sheetsApi!.spreadsheets.get(_spreadsheetId!));
    final existingSheets = spreadsheet.sheets ?? [];
    final existingTitles = existingSheets
        .map((s) => s.properties?.title ?? '')
        .where((t) => t.isNotEmpty)
        .toSet();

    final requests = <Request>[];
    for (final title in tabHeaders.keys) {
      if (!existingTitles.contains(title)) {
        requests.add(Request(
          addSheet: AddSheetRequest(
            properties: SheetProperties(title: title),
          ),
        ));
      }
    }

    if (requests.isNotEmpty) {
      dev.log('Adding ${requests.length} missing tabs');
      await _withRetry(() => _sheetsApi!.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(requests: requests),
        _spreadsheetId!,
      ));
    }

    final updatedSheet = await _withRetry(() => _sheetsApi!.spreadsheets.get(_spreadsheetId!));
    for (final sheet in (updatedSheet.sheets ?? [])) {
      final title = sheet.properties?.title;
      final sheetId = sheet.properties?.sheetId;
      if (title != null && sheetId != null) {
        _sheetNameToId[title] = sheetId;
      }
    }

    for (final title in tabHeaders.keys) {
      final headers = tabHeaders[title]!;
      final range = '$title!A1:${_columnLetter(headers.length - 1)}1';
      final existing = await _withRetry(() => _sheetsApi!.spreadsheets.values.get(
        _spreadsheetId!,
        range,
      ));
      if (existing.values == null || existing.values!.isEmpty) {
        dev.log('Writing header row for $title');
        await _withRetry(() => _sheetsApi!.spreadsheets.values.append(
          ValueRange(values: [headers]),
          _spreadsheetId!,
          range,
          valueInputOption: 'USER_ENTERED',
        ));
      }
    }
  }

  Future<int> appendRow(String tabName, List<String> values) async {
    final headers = tabHeaders[tabName]!;
    final range = '$tabName!A1:${_columnLetter(headers.length - 1)}1';
    final result = await _withRetry(() => _sheetsApi!.spreadsheets.values.append(
      ValueRange(values: [values]),
      _spreadsheetId!,
      range,
      valueInputOption: 'USER_ENTERED',
    ));
    final updatedRange = result.updates?.updatedRange ?? '';
    final match = RegExp(r'!A(\d+)').firstMatch(updatedRange);
    if (match != null) {
      return int.parse(match.group(1)!);
    }
    final allRows = await getAllRows(tabName);
    return allRows.length + 1;
  }

  Future<List<List<String>>> getAllRows(String tabName) async {
    final headers = tabHeaders[tabName]!;
    final range = '$tabName!A1:${_columnLetter(headers.length - 1)}';
    final result = await _withRetry(() => _sheetsApi!.spreadsheets.values.get(
      _spreadsheetId!,
      range,
    ));
    final values = result.values;
    if (values == null || values.length <= 1) return [];
    return values.sublist(1).map((row) {
      return List<String>.generate(headers.length, (i) {
        if (i < row.length && row[i] != null) return row[i].toString();
        return '';
      });
    }).toList();
  }

  Future<List<String>> getRow(String tabName, int rowIndex) async {
    final headers = tabHeaders[tabName]!;
    final range =
        '$tabName!A$rowIndex:${_columnLetter(headers.length - 1)}$rowIndex';
    final result = await _withRetry(() => _sheetsApi!.spreadsheets.values.get(
      _spreadsheetId!,
      range,
    ));
    final values = result.values;
    if (values == null || values.isEmpty) return [];
    final row = values.first;
    return List<String>.generate(headers.length, (i) {
      if (i < row.length && row[i] != null) return row[i].toString();
      return '';
    });
  }

  Future<void> updateRow(
    String tabName,
    int rowIndex,
    List<String> values,
  ) async {
    final range =
        '$tabName!A$rowIndex:${_columnLetter(values.length - 1)}$rowIndex';
    await _withRetry(() => _sheetsApi!.spreadsheets.values.update(
      ValueRange(values: [values]),
      _spreadsheetId!,
      range,
      valueInputOption: 'USER_ENTERED',
    ));
  }

  Future<void> clearRow(String tabName, int rowIndex, int columnCount) async {
    final range =
        '$tabName!A$rowIndex:${_columnLetter(columnCount - 1)}$rowIndex';
    await _withRetry(() => _sheetsApi!.spreadsheets.values.clear(
      ClearValuesRequest(),
      _spreadsheetId!,
      range,
    ));
  }

  Future<void> runRoundTripTest() async {
    dev.log('=== Round-trip test: writing test customer ===');
    final testCustomerId = '${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    final values = [
      testCustomerId, 'Test Customer', '9999999999',
      'test@example.com', 'Test Address', 'GST12345', now, now,
    ];

    final rowIndex = await appendRow('Customers', values);
    dev.log('Written to row $rowIndex');

    final readBack = await getRow('Customers', rowIndex);
    dev.log('Read back: $readBack');

    final allCustomers = await getAllRows('Customers');
    dev.log('All customers (${allCustomers.length}): $allCustomers');

    assert(readBack.isNotEmpty, 'Read-back should not be empty');
    assert(readBack[0] == testCustomerId, 'ID should match');
    dev.log('=== Round-trip test PASSED ===');
  }
}
