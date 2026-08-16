/// The workbook schema: one table per entity, per AGENTS.md §4.
///
/// This is the single place columns are declared. Backends create their tables
/// from it, and `test/schema_test.dart` asserts every model writes exactly
/// these keys.
class WorkbookSchema {
  WorkbookSchema._();

  /// Column order here is only used when creating a *new* header row. Reads and
  /// writes always follow the header row actually present in the workbook, so
  /// adding a column never shifts existing data.
  static const Map<String, List<String>> tables = {
    'Customers': [
      'customer_id', 'customer_code', 'name', 'phone', 'email',
      'street', 'area', 'city_district', 'state', 'country', 'pincode',
      'gst_number', 'tin_number', 'cst_number', 'created_at', 'updated_at',
    ],
    'Products': [
      'product_id', 'product_code', 'name', 'part_no', 'category', 'unit',
      'price', 'tax_percent', 'hsn_sac', 'created_at', 'updated_at',
    ],
    'PurchaseOrders': [
      'po_id', 'po_number', 'customer_id', 'order_date',
      'client_po_number', 'client_po_date',
      'client_delivery_note_number', 'client_delivery_note_date',
      'status', 'created_at', 'updated_at',
    ],
    'PurchaseOrderItems': [
      'po_item_id', 'po_id', 'product_id', 'quantity', 'rate',
      'delivered_qty', 'pending_qty', 'remarks', 'updated_at',
    ],
    'DeliveryNotes': [
      'dn_id', 'dn_number', 'po_id', 'delivery_date',
      'transport_mode', 'vehicle_number', 'created_at',
    ],
    'DeliveryNoteItems': [
      'dn_item_id', 'dn_id', 'po_item_id', 'delivered_qty', 'remarks',
    ],
    'Invoices': [
      'invoice_id', 'invoice_number', 'po_id', 'invoice_date',
      'subtotal_amount', 'cgst_percent', 'cgst_amount',
      'sgst_percent', 'sgst_amount', 'total_amount', 'amount_in_words',
      'transport_mode', 'vehicle_number', 'status', 'created_at',
    ],
    'InvoiceItems': [
      'invoice_item_id', 'invoice_id', 'po_item_id', 'product_id',
      'description', 'hsn_sac', 'quantity', 'rate', 'amount', 'remarks',
    ],
    'Counters': [
      'entity_name', 'category', 'financial_year', 'last_number',
    ],
    'CompanyProfile': [
      'company_name', 'street', 'area', 'city_district', 'state', 'country',
      'pincode', 'gst_number', 'tin_number', 'cst_number', 'phone', 'email',
      'website', 'logo_asset_path', 'updated_at',
    ],
  };

  static List<String> headersOf(String table) => tables[table]!;
  static Iterable<String> get tableNames => tables.keys;
  static bool hasColumn(String table, String column) =>
      tables[table]!.contains(column);
}

/// Row-level access to the workbook, independent of which cloud stores it.
///
/// ### Row addressing contract
/// `rowIndex` is the **1-based spreadsheet row**, where row 1 is the header row
/// and the first data row is 2. A backend whose native addressing differs (e.g.
/// Microsoft Graph table rows are 0-based and exclude the header) must convert
/// at its boundary, so repositories never need to know which backend is live.
///
/// ### Deletion contract
/// [clearRow] must **blank a row in place**, never remove it. Surviving rows
/// keep their indices, which is what lets a bulk delete capture indices once and
/// stay valid for the whole batch (AGENTS.md §10).
abstract class WorkbookStore {
  /// The header row actually present in the workbook for [table]. May contain
  /// extra trailing columns this app version doesn't know about.
  List<String> headersFor(String table);

  /// Every data row, in sheet order, keyed by column name. Blanked rows come
  /// back as empty maps so positional indices stay meaningful.
  Future<List<Map<String, String>>> getAllRows(String table);

  Future<Map<String, String>> getRow(String table, int rowIndex);

  /// Appends a row; returns the 1-based sheet row it landed on.
  Future<int> appendRow(String table, Map<String, String> row);

  Future<void> updateRow(String table, int rowIndex, Map<String, String> row);

  /// Blanks the row in place — see the deletion contract above.
  Future<void> clearRow(String table, int rowIndex);
}
